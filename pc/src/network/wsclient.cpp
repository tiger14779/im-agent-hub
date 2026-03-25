#include "wsclient.h"

#include <QJsonDocument>
#include <QJsonArray>
#include <QUrl>
#include <QUrlQuery>

WsClient::WsClient(QObject *parent)
    : QObject(parent)
{
    // 绑定 WebSocket 信号到对应槽函数
    connect(&m_ws, &QWebSocket::connected, this, &WsClient::onConnected);
    connect(&m_ws, &QWebSocket::disconnected, this, &WsClient::onDisconnected);
    connect(&m_ws, &QWebSocket::textMessageReceived, this, &WsClient::onTextMessageReceived);
    connect(&m_ws, &QWebSocket::errorOccurred, this, &WsClient::onError);

    // 断线后3秒尝试重连
    m_reconnectTimer.setInterval(3000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &WsClient::tryReconnect);
}

WsClient::~WsClient()
{
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

    // 构造 WebSocket 地址:  ws(s)://<host>/api/service/ws?staffId=xxx&token=xxx
    QString wsBase = baseUrl;
    wsBase.replace(QStringLiteral("http://"), QStringLiteral("ws://"));
    wsBase.replace(QStringLiteral("https://"), QStringLiteral("wss://"));

    QUrl url(wsBase + "/api/service/ws");
    QUrlQuery query;
    query.addQueryItem("staffId", staffId);
    query.addQueryItem("token", token);
    url.setQuery(query);

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
    QJsonObject data;
    data["peerUserId"] = peerUserId;

    QJsonObject envelope;
    envelope["type"] = QStringLiteral("load_history");
    envelope["data"] = data;

    m_ws.sendTextMessage(QJsonDocument(envelope).toJson(QJsonDocument::Compact));
}

void WsClient::onConnected()
{
    m_connected = true;
    m_reconnectAttempts = 0;
    emit connectedChanged();
}

void WsClient::onDisconnected()
{
    m_connected = false;
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
    Q_UNUSED(error)
    emit connectionError(m_ws.errorString());
}

void WsClient::tryReconnect()
{
    // 最多尝试10次重连，超过则放弃
    if (m_reconnectAttempts >= 10 || m_baseUrl.isEmpty()) return;
    m_reconnectAttempts++;
    connectToServer(m_baseUrl, m_staffId, m_token);
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
