#include "wsclient.h"

#include <QJsonDocument>
#include <QJsonArray>
#include <QUrl>
#include <QDebug>
#include <QUrlQuery>
#include <QNetworkProxy>

WsClient::WsClient(QObject *parent)
    : QObject(parent)
{
    // 禁用系统代理，避免代理不支持 WebSocket 导致连接失败
    m_ws.setProxy(QNetworkProxy::NoProxy);

    // 绑定 WebSocket 信号到对应槽函数
    connect(&m_ws, &QWebSocket::connected, this, &WsClient::onConnected);
    connect(&m_ws, &QWebSocket::disconnected, this, &WsClient::onDisconnected);
    connect(&m_ws, &QWebSocket::textMessageReceived, this, &WsClient::onTextMessageReceived);
    connect(&m_ws, &QWebSocket::errorOccurred, this, &WsClient::onError);

    // 断线后重连（首次立即，后续指数退避）
    m_reconnectTimer.setInterval(3000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &WsClient::tryReconnect);

    // 每15秒发送一次心跳 ping，防止连接被中间网络设备关闭
    m_pingTimer.setInterval(15000);
    connect(&m_pingTimer, &QTimer::timeout, this, &WsClient::sendPing);

    // 每2秒检查一次 ACK 超时
    m_ackCheckTimer.setInterval(2000);
    connect(&m_ackCheckTimer, &QTimer::timeout, this, &WsClient::checkAckTimeouts);
}

WsClient::~WsClient()
{
    m_pingTimer.stop();
    m_ackCheckTimer.stop();
    m_reconnectTimer.stop();
    m_reconnectTimer.disconnect();
    m_pendingSends.clear();
    m_baseUrl.clear();            // 阻止 onDisconnected 中触发重连
    m_ws.disconnect();            // 断开所有信号连接
    if (m_ws.state() != QAbstractSocket::UnconnectedState)
        m_ws.close();
}

void WsClient::connectToServer(const QString &baseUrl, const QString &staffId, const QString &token)
{
    m_baseUrl = baseUrl;
    m_staffId = staffId;
    m_token = token;
    m_reconnectAttempts = 0;
    m_reconnectTimer.stop();
    m_reconnectTimer.setInterval(3000);

    doConnect();
}

void WsClient::doConnect()
{
    // 确保关闭之前的连接，避免状态残留导致信号不触发
    m_ws.abort();

    // 构造 WebSocket 地址:  ws(s)://<host>/api/service/ws?staffId=xxx&token=xxx
    QString wsBase = m_baseUrl;
    // 去掉末尾斜杠，避免拼接出双斜杠
    while (wsBase.endsWith('/'))
        wsBase.chop(1);
    wsBase.replace(QStringLiteral("http://"), QStringLiteral("ws://"));
    wsBase.replace(QStringLiteral("https://"), QStringLiteral("wss://"));

    QUrl url(wsBase + "/api/service/ws");
    QUrlQuery query;
    query.addQueryItem("staffId", m_staffId);
    query.addQueryItem("token", m_token);
    url.setQuery(query);

    qDebug() << "[WsClient] doConnect url=" << url.toString();
    m_ws.open(url);
}

void WsClient::disconnect()
{
    m_reconnectTimer.stop();
    m_ackCheckTimer.stop();
    m_baseUrl.clear();
    // 主动断开：所有待发消息标记失败
    for (auto it = m_pendingSends.begin(); it != m_pendingSends.end(); ++it) {
        emit messageAck(it.key(), 3, QString(), 0);
    }
    m_pendingSends.clear();
    m_ws.close();
}

void WsClient::sendMessage(const QString &recvId, int contentType,
                             const QString &content, const QString &clientMsgId)
{
    qDebug() << "[WsClient] sendMessage connected=" << m_connected << "recvId=" << recvId << "type=" << contentType;

    // 加入待发送队列
    PendingSend ps;
    ps.recvId = recvId;
    ps.contentType = contentType;
    ps.content = content;
    ps.clientMsgId = clientMsgId;
    ps.retries = 0;
    ps.sentAt = 0;
    m_pendingSends.insert(clientMsgId, ps);

    if (m_connected) {
        doSendMessage(m_pendingSends[clientMsgId]);
    }
    // 未连接时消息留在队列中，重连后 flushPendingSends() 会自动发送
}

void WsClient::doSendMessage(PendingSend &ps)
{
    QJsonObject data;
    data["recvId"] = ps.recvId;
    data["contentType"] = ps.contentType;
    data["clientMsgId"] = ps.clientMsgId;

    // 将 content 字符串解析为 JSON 对象，避免双重转义
    QJsonDocument contentDoc = QJsonDocument::fromJson(ps.content.toUtf8());
    if (contentDoc.isObject())
        data["content"] = contentDoc.object();
    else
        data["content"] = ps.content;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("send_message");
    envelope["data"] = data;

    QByteArray payload = QJsonDocument(envelope).toJson(QJsonDocument::Compact);
    qDebug() << "[WsClient] doSendMessage msgId=" << ps.clientMsgId
             << "payloadSize=" << payload.size() << "connected=" << m_connected
             << "wsState=" << m_ws.state();
    qint64 sent = m_ws.sendTextMessage(QString::fromUtf8(payload));
    if (sent == 0) {
        qDebug() << "[WsClient] sendTextMessage returned 0! Message may not have been sent.";
    }
    ps.sentAt = QDateTime::currentMSecsSinceEpoch();
}

void WsClient::flushPendingSends()
{
    auto it = m_pendingSends.begin();
    while (it != m_pendingSends.end()) {
        it->retries++;
        if (it->retries > MAX_RETRIES) {
            QString id = it.key();
            it = m_pendingSends.erase(it);
            qDebug() << "[WsClient] message failed after retries:" << id;
            emit messageAck(id, 3, QString(), 0);
            continue;
        }
        qDebug() << "[WsClient] resending pending message:" << it.key() << "retry" << it->retries;
        doSendMessage(it.value());
        ++it;
    }
}

void WsClient::checkAckTimeouts()
{
    if (!m_connected) return;
    auto now = QDateTime::currentMSecsSinceEpoch();
    auto it = m_pendingSends.begin();
    while (it != m_pendingSends.end()) {
        if (it->sentAt > 0 && (now - it->sentAt) > ACK_TIMEOUT_MS) {
            QString id = it.key();
            it = m_pendingSends.erase(it);
            qDebug() << "[WsClient] ACK timeout for" << id;
            emit messageAck(id, 3, QString(), 0);
        } else {
            ++it;
        }
    }
}

void WsClient::loadHistory(const QString &peerUserId, qint64 beforeSeq, int limit, qint64 afterSeq)
{
    qDebug() << "[WsClient] loadHistory connected=" << m_connected << "peerUserId=" << peerUserId
             << "beforeSeq=" << beforeSeq << "afterSeq=" << afterSeq << "limit=" << limit;

    if (!m_connected) {
        qDebug() << "[WsClient] loadHistory skipped: not connected, saving pending request";
        m_pendingHistoryPeer = peerUserId;
        m_pendingHistorySeq = beforeSeq;
        m_pendingHistoryLimit = limit;
        return;
    }

    m_pendingHistoryPeer.clear(); // clear any pending request

    QJsonObject data;
    data["peerUserId"] = peerUserId;
    if (afterSeq > 0)
        data["afterSeq"] = afterSeq;  // 增量模式
    else if (beforeSeq > 0)
        data["beforeSeq"] = beforeSeq; // 向上翻页模式
    data["limit"] = limit;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("load_history");
    envelope["data"] = data;

    m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
}

void WsClient::onConnected()
{
    qDebug() << "[WsClient] onConnected! WS connection established";
    m_connected = true;
    m_reconnectAttempts = 0;
    m_reconnectTimer.setInterval(3000); // 重置重连间隔
    m_pingTimer.start();
    m_ackCheckTimer.start();
    emit connectedChanged();
    flushPendingSends();

    // 重连后重发挂起的历史请求
    if (!m_pendingHistoryPeer.isEmpty()) {
        qDebug() << "[WsClient] resending pending loadHistory for" << m_pendingHistoryPeer;
        QString peer = m_pendingHistoryPeer;
        qint64 seq = m_pendingHistorySeq;
        int limit = m_pendingHistoryLimit;
        m_pendingHistoryPeer.clear();
        loadHistory(peer, seq, limit);
    }
}

void WsClient::onDisconnected()
{
    qDebug() << "[WsClient] onDisconnected! baseUrl=" << m_baseUrl;
    m_connected = false;
    m_pingTimer.stop();
    m_ackCheckTimer.stop();
    emit connectedChanged();
    // 若 m_baseUrl 非空，说明非主动断开，启动重连
    if (!m_baseUrl.isEmpty() && !m_reconnectTimer.isActive()) {
        if (m_reconnectAttempts == 0) {
            // 首次断线：立即重连（0ms 延迟）
            m_reconnectTimer.setInterval(0);
        }
        m_reconnectTimer.start();
    }
}

void WsClient::onTextMessageReceived(const QString &message)
{
    QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (doc.isObject())
        handleWsMessage(doc.object());
}

void WsClient::onError(QAbstractSocket::SocketError error)
{
    qDebug() << "[WsClient] onError:" << error << m_ws.errorString();
    Q_UNUSED(error)
    emit connectionError(m_ws.errorString());
    // 连接未建立就失败时 onDisconnected 可能不触发，手动启动重连
    if (!m_connected && !m_baseUrl.isEmpty() && !m_reconnectTimer.isActive()) {
        if (m_reconnectAttempts == 0)
            m_reconnectTimer.setInterval(0);
        m_reconnectTimer.start();
    }
}

void WsClient::tryReconnect()
{
    if (m_baseUrl.isEmpty()) return;
    m_reconnectAttempts++;
    // 指数退避：0 → 1s → 3s → 6s → 12s → 30s(上限)
    static const int delays[] = {1000, 3000, 6000, 12000, 30000};
    int idx = qMin(m_reconnectAttempts - 1, 4);
    int nextDelay = delays[idx];
    m_reconnectTimer.setInterval(nextDelay);
    qDebug() << "[WsClient] tryReconnect attempt" << m_reconnectAttempts << "nextDelay=" << nextDelay << "ms";
    doConnect();
}

void WsClient::sendPing()
{
    if (m_connected) {
        QJsonObject envelope;
        envelope["type"] = QStringLiteral("ping");
        envelope["data"] = QJsonObject();
        m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
    }
}

void WsClient::deleteMessage(const QString &serverMsgId)
{
    if (!m_connected || serverMsgId.isEmpty()) return;

    QJsonObject data;
    data["serverMsgId"] = serverMsgId;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("delete_message");
    envelope["data"] = data;

    m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
}

void WsClient::queryOnline()
{
    if (!m_connected) return;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("query_online");
    envelope["data"] = QJsonObject();

    m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
}

void WsClient::sendGroupMessage(const QString &groupId, int contentType,
                                  const QString &content, const QString &clientMsgId)
{
    QJsonObject data;
    data["groupId"] = groupId;
    data["contentType"] = contentType;
    data["clientMsgId"] = clientMsgId;

    QJsonDocument contentDoc = QJsonDocument::fromJson(content.toUtf8());
    if (contentDoc.isObject())
        data["content"] = contentDoc.object();
    else
        data["content"] = content;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("send_group_message");
    envelope["data"] = data;

    m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
}

void WsClient::handleWsMessage(const QJsonObject &envelope)
{
    QString type = envelope["type"].toString();
    QJsonObject data = envelope["data"].toObject();

    if (type == "new_message") {
        qDebug() << "[WsClient] new_message received: sendID=" << data["sendID"].toString()
                 << "recvID=" << data["recvID"].toString()
                 << "type=" << data["contentType"].toInt()
                 << "clientMsgID=" << data["clientMsgID"].toString();
        emit newMessage(data);
    } else if (type == "message_ack") {
        QString clientMsgId = data["clientMsgId"].toString();
        m_pendingSends.remove(clientMsgId); // ACK 已收到，从队列移除
        int status = data["status"].toInt(2);
        QString serverMsgId = data["serverMsgId"].toString();
        qint64 sendTime = static_cast<qint64>(data["sendTime"].toDouble());
        QString error = data["error"].toString();
        qDebug() << "[WsClient] message_ack: clientMsgId=" << clientMsgId
                 << "status=" << status << "serverMsgId=" << serverMsgId
                 << "sendTime=" << sendTime << "error=" << error;
        emit messageAck(clientMsgId, status, serverMsgId, sendTime);
    } else if (type == "history") {
        QString peerUserId = data["peerUserId"].toString();
        QJsonArray messages = data["messages"].toArray();
        bool hasMore = data["hasMore"].toBool(false);
        emit historyLoaded(peerUserId, messages, hasMore);
    } else if (type == "contacts_updated") {
        emit contactsUpdated();
    } else if (type == "message_deleted" || type == "delete_ack") {
        QString serverMsgId = data["serverMsgId"].toString();
        if (!serverMsgId.isEmpty())
            emit messageDeleted(serverMsgId);
    } else if (type == "client_online_status") {
        QString userId = data["userId"].toString();
        QString status = data["status"].toString();
        if (!userId.isEmpty())
            emit clientOnlineStatus(userId, status);
    } else if (type == "online_list") {
        QJsonArray clients = data["clients"].toArray();
        emit onlineListReceived(clients);
    } else if (type == "group_member_added") {
        QString groupId  = data["groupId"].toString();
        QString userId   = data["userId"].toString();
        QString nickname = data["nickname"].toString();
        emit groupMemberAdded(groupId, userId, nickname);
    } else if (type == "group_member_removed") {
        QString groupId = data["groupId"].toString();
        QString userId  = data["userId"].toString();
        emit groupMemberRemoved(groupId, userId);
    } else if (type == "group_dissolved") {
        QString groupId = data["groupId"].toString();
        emit groupDissolved(groupId);
    } else if (type == "group_info_updated") {
        QString groupId = data["groupId"].toString();
        QString name    = data["name"].toString();
        QString avatar  = data["avatar"].toString();
        emit groupInfoUpdated(groupId, name, avatar);
    } else if (type == "new_group_message") {
        qDebug() << "[WsClient] new_group_message groupId=" << data["groupId"].toString()
                 << "sendId=" << data["sendId"].toString()
                 << "senderName=" << data["senderName"].toString();
        emit newGroupMessage(data);
    // ── 通话信令 ──────────────────────────────────────────────────
    } else if (type == "call_invite") {
        QString fromId   = data["fromId"].toString();
        QString fromName = data["fromName"].toString();
        qDebug() << "[WsClient] call_invite from=" << fromId;
        emit callInviteReceived(fromId, fromName);
    } else if (type == "call_accept") {
        QString fromId = data["fromId"].toString();
        qDebug() << "[WsClient] call_accept from=" << fromId;
        emit callAccepted(fromId);
    } else if (type == "call_audio_ready") {
        QString roomId = data["roomId"].toString();
        QString token  = data["token"].toString();
        QString wsBase = data["wsBase"].toString();
        qDebug() << "[WsClient] call_audio_ready room=" << roomId;
        emit callAudioReady(roomId, token, wsBase);
    } else if (type == "call_reject") {
        QString fromId = data["fromId"].toString();
        qDebug() << "[WsClient] call_reject from=" << fromId;
        emit callRejected(fromId);
    } else if (type == "call_busy") {
        QString fromId = data["fromId"].toString();
        qDebug() << "[WsClient] call_busy from=" << fromId;
        emit callBusy(fromId);
    } else if (type == "call_end") {
        QString fromId = data["fromId"].toString();
        qDebug() << "[WsClient] call_end from=" << fromId;
        emit callEnded(fromId);
    }
}

void WsClient::sendCallInvite(const QString &toId, const QString &fromName)
{
    if (!m_connected) return;
    QJsonObject data;
    data["toId"]     = toId;
    data["fromId"]   = m_staffId;
    data["fromName"] = fromName;
    QJsonObject env;
    env["type"] = QStringLiteral("call_invite");
    env["data"] = data;
    m_ws.sendTextMessage(QJsonDocument(env).toJson(QJsonDocument::Compact));
}

void WsClient::sendCallAccept(const QString &toId)
{
    if (!m_connected) return;
    QJsonObject data;
    data["toId"]   = toId;
    data["fromId"] = m_staffId;
    QJsonObject env;
    env["type"] = QStringLiteral("call_accept");
    env["data"] = data;
    m_ws.sendTextMessage(QJsonDocument(env).toJson(QJsonDocument::Compact));
}

void WsClient::sendCallReject(const QString &toId)
{
    if (!m_connected) return;
    QJsonObject data;
    data["toId"]   = toId;
    data["fromId"] = m_staffId;
    QJsonObject env;
    env["type"] = QStringLiteral("call_reject");
    env["data"] = data;
    m_ws.sendTextMessage(QJsonDocument(env).toJson(QJsonDocument::Compact));
}

void WsClient::sendCallEnd(const QString &toId)
{
    if (!m_connected) return;
    QJsonObject data;
    data["toId"]   = toId;
    data["fromId"] = m_staffId;
    QJsonObject env;
    env["type"] = QStringLiteral("call_end");
    env["data"] = data;
    m_ws.sendTextMessage(QJsonDocument(env).toJson(QJsonDocument::Compact));
}
