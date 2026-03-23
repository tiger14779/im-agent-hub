#include "wsclient.h"

#include <QJsonDocument>
#include <QJsonArray>
#include <QUrl>
#include <QUrlQuery>

WsClient::WsClient(QObject *parent)
    : QObject(parent)
{
    connect(&m_ws, &QWebSocket::connected, this, &WsClient::onConnected);
    connect(&m_ws, &QWebSocket::disconnected, this, &WsClient::onDisconnected);
    connect(&m_ws, &QWebSocket::textMessageReceived, this, &WsClient::onTextMessageReceived);
    connect(&m_ws, &QWebSocket::errorOccurred, this, &WsClient::onError);

    m_reconnectTimer.setInterval(3000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &WsClient::tryReconnect);
}

void WsClient::connectToServer(const QString &baseUrl, const QString &staffId, const QString &token)
{
    m_baseUrl = baseUrl;
    m_staffId = staffId;
    m_token = token;
    m_reconnectAttempts = 0;

    // Build WS URL:  ws(s)://<host>/api/service/ws?staffId=xxx&token=xxx
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

    // Parse content string as JSON object so it embeds properly (not double-escaped)
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
    }
}
