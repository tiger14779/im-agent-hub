#include "wxbridge.h"

#include <QTcpSocket>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <QUrl>
#include <QDateTime>
#include <QDebug>

WxBridge::WxBridge(QObject *parent)
    : QObject(parent)
{
}

WxBridge::~WxBridge()
{
    stopServer();
}

// ── HTTP API Server on port 8888 ────────────────────────

bool WxBridge::startServer()
{
    if (m_server) {
        stopServer();
    }

    m_server = new QTcpServer(this);
    connect(m_server, &QTcpServer::newConnection, this, &WxBridge::onNewConnection);

    if (!m_server->listen(QHostAddress::Any, static_cast<quint16>(m_apiPort))) {
        QString err = m_server->errorString();
        qWarning() << "[WxBridge] Failed to listen on port" << m_apiPort << err;
        delete m_server;
        m_server = nullptr;
        emit bridgeError("监听端口 " + QString::number(m_apiPort) + " 失败: " + err);
        return false;
    }

    m_listening = true;
    emit listeningChanged();
    qDebug() << "[WxBridge] API server listening on port" << m_apiPort;
    return true;
}

void WxBridge::stopServer()
{
    if (m_server) {
        m_server->close();
        // Close all active sockets immediately (don't rely on deleteLater)
        for (auto it = m_buffers.begin(); it != m_buffers.end(); ++it) {
            QTcpSocket *sock = it.key();
            sock->disconnect();        // detach all signals
            sock->abort();             // force-close immediately
            delete sock;
        }
        m_buffers.clear();
        delete m_server;
        m_server = nullptr;
    }
    m_listening = false;
    emit listeningChanged();
    qDebug() << "[WxBridge] API server stopped";
}

void WxBridge::onNewConnection()
{
    while (m_server->hasPendingConnections()) {
        QTcpSocket *socket = m_server->nextPendingConnection();

        connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
            m_buffers[socket].append(socket->readAll());

            if (!m_buffers[socket].contains("\r\n\r\n"))
                return;

            QString fullRequest = QString::fromUtf8(m_buffers[socket]);
            int headerEnd = fullRequest.indexOf("\r\n\r\n");
            QString headers = fullRequest.left(headerEnd);

            static QRegularExpression clRegex(
                "Content-Length:\\s*(\\d+)", QRegularExpression::CaseInsensitiveOption);
            QRegularExpressionMatch match = clRegex.match(headers);
            int expectedBody = match.hasMatch() ? match.captured(1).toInt() : 0;

            int currentBody = m_buffers[socket].size() - (headerEnd + 4);
            if (currentBody < expectedBody)
                return;

            QString body = fullRequest.mid(headerEnd + 4);
            qDebug() << "[WxBridge] API request:" << body.left(300);

            m_buffers.remove(socket);
            handleApiRequest(body, socket);
        });

        connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
            m_buffers.remove(socket);
            socket->deleteLater();
        });
    }
}

// ── Handle incoming API commands from accounting software ──

void WxBridge::handleApiRequest(const QString &body, QTcpSocket *socket)
{
    auto sendResponse = [socket](const QJsonObject &resp) {
        QByteArray respData = QJsonDocument(resp).toJson(QJsonDocument::Compact);
        QByteArray http =
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: application/json; charset=utf-8\r\n"
            "Content-Length: " + QByteArray::number(respData.size()) + "\r\n"
            "Connection: close\r\n"
            "\r\n" + respData;
        socket->write(http);
        socket->flush();
        socket->disconnectFromHost();
    };

    QJsonDocument doc = QJsonDocument::fromJson(body.toUtf8());
    if (!doc.isObject()) {
        sendResponse({{"status", "error"}, {"msg", "invalid json"}});
        return;
    }

    QJsonObject root = doc.object();
    QString type = root["type"].toString();
    QJsonObject data = root["data"].toObject();

    qDebug() << "[WxBridge] Command type:" << type;

    if (type == "Q0001") {
        // Send text message
        QString wxid = data["wxid"].toString();
        QString msg  = data["msg"].toString();
        if (!wxid.isEmpty() && !msg.isEmpty()) {
            emit apiSendText(wxid, msg);
            sendResponse({{"status", "ok"}, {"type", type}});
        } else {
            sendResponse({{"status", "error"}, {"msg", "missing wxid or msg"}});
        }

    } else if (type == "Q0011") {
        // Send image
        QString wxid = data["wxid"].toString();
        QString path = data["path"].toString();
        if (!wxid.isEmpty() && !path.isEmpty()) {
            emit apiSendImage(wxid, path);
            sendResponse({{"status", "ok"}, {"type", type}});
        } else {
            sendResponse({{"status", "error"}, {"msg", "missing wxid or path"}});
        }

    } else if (type == "Q0030") {
        // Send file
        QString wxid = data["wxid"].toString();
        QString path = data["path"].toString();
        if (!wxid.isEmpty() && !path.isEmpty()) {
            emit apiSendFile(wxid, path);
            sendResponse({{"status", "ok"}, {"type", type}});
        } else {
            sendResponse({{"status", "error"}, {"msg", "missing wxid or path"}});
        }

    } else if (type == "Q0005") {
        // Get friend list — emit signal, QML will respond
        emit apiGetFriendList();
        sendResponse({{"status", "ok"}, {"type", type}});

    } else {
        sendResponse({{"status", "error"}, {"msg", "unknown type: " + type}});
    }
}

// ── Push message events to accounting software on port 7888 ──

void WxBridge::pushMessageEvent(const QString &fromId, const QString &toId,
                                 const QString &msg, bool isSelf, int wxType)
{
    qint64 now = QDateTime::currentSecsSinceEpoch();

    QJsonObject data;
    data["fromType"]     = 1;  // 1 = private chat
    data["msgSource"]    = isSelf ? 1 : 0;  // 0=received, 1=self-sent
    data["fromWxid"]     = fromId;
    data["toWxid"]       = toId;
    data["msg"]          = msg;
    data["wxType"]       = wxType;
    data["timestamp"]    = now;

    QJsonObject payload;
    payload["type"] = QStringLiteral("message");
    payload["data"] = data;

    qDebug() << "[WxBridge] Pushing event to 7888, from:" << fromId << "to:" << toId;
    pushToCallback(payload);
}

void WxBridge::pushFriendList(const QJsonArray &contacts)
{
    QJsonObject payload;
    payload["type"]   = QStringLiteral("Q0005");
    payload["result"] = contacts;

    qDebug() << "[WxBridge] Pushing friend list to 7888, count:" << contacts.size();
    pushToCallback(payload);
}

void WxBridge::pushToCallback(const QJsonObject &payload)
{
    QUrl url(QStringLiteral("http://127.0.0.1:%1").arg(m_callbackPort));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QByteArray body = QJsonDocument(payload).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = m_nam.post(req, body);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[WxBridge] Push to 7888 failed:" << reply->errorString();
        } else {
            qDebug() << "[WxBridge] Push to 7888 OK";
        }
    });
}

