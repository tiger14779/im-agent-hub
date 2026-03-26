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

    // 断线后3秒尝试重连
    m_reconnectTimer.setInterval(3000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &WsClient::tryReconnect);

    // 每25秒发送一次心跳 ping，防止连接被中间网络设备关闭
    m_pingTimer.setInterval(25000);
    connect(&m_pingTimer, &QTimer::timeout, this, &WsClient::sendPing);
}

WsClient::~WsClient()
{
    m_pingTimer.stop();
    m_reconnectTimer.stop();
    m_reconnectTimer.disconnect();
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
    m_baseUrl.clear();
    m_ws.close();
}

void WsClient::sendMessage(const QString &recvId, int contentType,
                             const QString &content, const QString &clientMsgId)
{
    qDebug() << "[WsClient] sendMessage connected=" << m_connected << "recvId=" << recvId << "type=" << contentType;
    QJsonObject data;
    data["recvId"] = recvId;
    data["contentType"] = contentType;
    data["clientMsgId"] = clientMsgId;

    // 将 content 字符串解析为 JSON 对象，避免双重转义
    QJsonDocument contentDoc = QJsonDocument::fromJson(content.toUtf8());
    if (contentDoc.isObject())
        data["content"] = contentDoc.object();
    else
        data["content"] = content;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("send_message");
    envelope["data"] = data;

    m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
}

void WsClient::loadHistory(const QString &peerUserId)
{
    qDebug() << "[WsClient] loadHistory connected=" << m_connected << "peerUserId=" << peerUserId;
    QJsonObject data;
    data["peerUserId"] = peerUserId;

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
    m_pingTimer.start();
    emit connectedChanged();
}

void WsClient::onDisconnected()
{
    qDebug() << "[WsClient] onDisconnected! baseUrl=" << m_baseUrl;
    m_connected = false;
    m_pingTimer.stop();
    emit connectedChanged();
    // 若 m_baseUrl 非空，说明非主动断开，启动重连定时器
    if (!m_baseUrl.isEmpty())
        m_reconnectTimer.start();
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
        m_reconnectTimer.start();
    }
}

void WsClient::tryReconnect()
{
    if (m_baseUrl.isEmpty()) {
        return;
    }
    m_reconnectAttempts++;
    // 指数退避：3s → 6s → 12s → 24s → 48s → 60s(上限)
    int delay = qMin(3000 * (1 << qMin(m_reconnectAttempts, 4)), 60000);
    m_reconnectTimer.setInterval(delay);
    qDebug() << "[WsClient] tryReconnect attempt" << m_reconnectAttempts << "nextDelay=" << delay << "ms";
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

void WsClient::handleWsMessage(const QJsonObject &envelope)
{
    QString type = envelope["type"].toString();
    QJsonObject data = envelope["data"].toObject();

    if (type == "new_message") {
        emit newMessage(data);
    } else if (type == "message_ack") {
        QString clientMsgId = data["clientMsgId"].toString();
        int status = data["status"].toInt(2);
        QString serverMsgId = data["serverMsgId"].toString();
        qint64 sendTime = static_cast<qint64>(data["sendTime"].toDouble());
        emit messageAck(clientMsgId, status, serverMsgId, sendTime);
    } else if (type == "history") {
        QString peerUserId = data["peerUserId"].toString();
        QJsonArray messages = data["messages"].toArray();
        emit historyLoaded(peerUserId, messages);
    } else if (type == "contacts_updated") {
        emit contactsUpdated();
    }
}
