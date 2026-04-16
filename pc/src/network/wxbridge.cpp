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

// ── HTTP API 服务（端口 8888）────────────────────────────────

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
        // 立即关闭所有活跃的 Socket 连接（不依赖 deleteLater）
        for (auto it = m_buffers.begin(); it != m_buffers.end(); ++it) {
            QTcpSocket *sock = it.key();
            sock->disconnect();        // 断开所有信号
            sock->abort();             // 强制关闭连接
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

            // 使用原始字节在 QByteArray 上查找 header 结束位置，
            // 避免 UTF-8 → QString 转换导致字节偏移与字符偏移不一致
            int headerEndBytes = m_buffers[socket].indexOf("\r\n\r\n");
            if (headerEndBytes < 0)
                return;

            // 从原始字节中解析 Content-Length
            QByteArray headersPart = m_buffers[socket].left(headerEndBytes);
            static QRegularExpression clRegex(
                "Content-Length:\\s*(\\d+)", QRegularExpression::CaseInsensitiveOption);
            QRegularExpressionMatch match = clRegex.match(QString::fromLatin1(headersPart));
            int expectedBody = match.hasMatch() ? match.captured(1).toInt() : 0;

            int currentBody = m_buffers[socket].size() - (headerEndBytes + 4);
            if (currentBody < expectedBody)
                return;

            // 精确提取 Content-Length 字节的 body（防止 HTTP 管线化串扰）
            QByteArray rawBody = m_buffers[socket].mid(headerEndBytes + 4, expectedBody);
            QString body = QString::fromUtf8(rawBody);
            qDebug() << "[WxBridge] API request:" << body.left(500);

            m_buffers.remove(socket);
            handleApiRequest(body, socket);
        });

        connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
            m_buffers.remove(socket);
            socket->deleteLater();
        });
    }
}

// ── 处理财务软件下发的 API 指令 ───────────────────

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

    // 文件/图片发送去重：5秒内相同 type+wxid+path 的请求只处理一次
    if (type == "Q0011" || type == "Q0030") {
        QString dedupKey = type + "|" + data["wxid"].toString() + "|" + data["path"].toString();
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (m_recentCommands.contains(dedupKey) && (now - m_recentCommands[dedupKey]) < 5000) {
            qDebug() << "[WxBridge] Dedup: ignoring duplicate" << type << "within 5s window";
            sendResponse({{"status", "ok"}, {"type", type}, {"dedup", true}});
            return;
        }
        m_recentCommands[dedupKey] = now;
        // 清理过期去重记录（超过10秒）
        for (auto it = m_recentCommands.begin(); it != m_recentCommands.end(); ) {
            if (now - it.value() > 10000) it = m_recentCommands.erase(it);
            else ++it;
        }
    }

    if (type == "Q0001") {
        // 发送文本消息
        QString wxid = data["wxid"].toString();
        QString msg  = data["msg"].toString();
        if (!wxid.isEmpty() && !msg.isEmpty()) {
            emit apiSendText(wxid, msg);
            sendResponse({{"status", "ok"}, {"type", type}});
        } else {
            sendResponse({{"status", "error"}, {"msg", "missing wxid or msg"}});
        }

    } else if (type == "Q0011") {
        // 发送图片
        QString wxid = data["wxid"].toString();
        QString path = data["path"].toString();
        if (!wxid.isEmpty() && !path.isEmpty()) {
            emit apiSendImage(wxid, path);
            sendResponse({{"status", "ok"}, {"type", type}});
        } else {
            sendResponse({{"status", "error"}, {"msg", "missing wxid or path"}});
        }

    } else if (type == "Q0030") {
        // 发送文件
        QString wxid = data["wxid"].toString();
        QString path = data["path"].toString();
        qDebug() << "[WxBridge] Q0030 file send: wxid=" << wxid << "path=" << path
                 << "pathLen=" << path.length();
        if (!wxid.isEmpty() && !path.isEmpty()) {
            emit apiSendFile(wxid, path);
            sendResponse({{"status", "ok"}, {"type", type}});
        } else {
            sendResponse({{"status", "error"}, {"msg", "missing wxid or path"}});
        }

    } else if (type == "Q0005") {
        // 获取好友列表 —— 发出信号，由 QML 层响应
        emit apiGetFriendList();
        sendResponse({{"status", "ok"}, {"type", type}});

    } else {
        sendResponse({{"status", "error"}, {"msg", "unknown type: " + type}});
    }
}

// ── 推送消息事件到财务软件（端口 7888）───────────

void WxBridge::pushMessageEvent(const QString &fromId, const QString &toId,
                                 const QString &msg, bool isSelf, int wxType)
{
    qint64 now = QDateTime::currentSecsSinceEpoch();

    QJsonObject data;
    data["fromType"]     = 1;  // 1 = 私聊
    data["msgSource"]    = isSelf ? 1 : 0;  // 0=接收, 1=自发
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

// ── LiveKit 信令 WebSocket 代理 ───────────────────────────────────────────
// 用 Qt 的 QWebSocket (Windows Schannel TLS) 代理连接到 wss://livekit...
// 解决 QtWebEngine Chromium BoringSSL 与 LiveKit TLS 不兼容的问题

bool WxBridge::startLivekitProxy(const QString &realWsBaseUrl, quint16 localPort)
{
    stopLivekitProxy();

    m_livekitBaseWsUrl = realWsBaseUrl;
    m_wsProxyServer = new QWebSocketServer(
        QStringLiteral("LiveKitProxy"),
        QWebSocketServer::NonSecureMode,
        this);

    if (!m_wsProxyServer->listen(QHostAddress::LocalHost, localPort)) {
        qWarning() << "[LKProxy] Failed to listen on port" << localPort
                   << m_wsProxyServer->errorString();
        delete m_wsProxyServer;
        m_wsProxyServer = nullptr;
        return false;
    }

    connect(m_wsProxyServer, &QWebSocketServer::newConnection, this, [this]() {
        QWebSocket *local = m_wsProxyServer->nextPendingConnection();
        if (!local) return;

        // 把本地连接 URL 的 path+query 拼接到真实 LiveKit 地址
        QUrl remoteUrl(m_livekitBaseWsUrl
                       + local->requestUrl().path()
                       + (local->requestUrl().hasQuery()
                              ? QStringLiteral("?") + local->requestUrl().query()
                              : QString()));
        qDebug() << "[LKProxy] new local connection, forwarding to" << remoteUrl;

        QWebSocket *remote = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);

        // 忽略 SSL 错误（使用系统 Schannel 时通常不需要，但保险起见）
        connect(remote, QOverload<const QList<QSslError>&>::of(&QWebSocket::sslErrors),
                remote, [remote](const QList<QSslError> &errors) {
            qWarning() << "[LKProxy] SSL errors (ignored):" << errors;
            remote->ignoreSslErrors();
        });

        m_proxyLocal2Remote[local] = remote;

        // 本地 → 远端
        connect(local, &QWebSocket::textMessageReceived,
                remote, &QWebSocket::sendTextMessage);
        connect(local, &QWebSocket::binaryMessageReceived,
                remote, &QWebSocket::sendBinaryMessage);

        // 远端 → 本地
        connect(remote, &QWebSocket::textMessageReceived,
                local, &QWebSocket::sendTextMessage);
        connect(remote, &QWebSocket::binaryMessageReceived,
                local, &QWebSocket::sendBinaryMessage);

        // 任意一端断开，关闭另一端
        connect(local, &QWebSocket::disconnected, this, [this, local]() {
            qDebug() << "[LKProxy] local disconnected";
            if (QWebSocket *r = m_proxyLocal2Remote.take(local)) {
                r->close();
                r->deleteLater();
            }
            local->deleteLater();
        });
        connect(remote, &QWebSocket::disconnected, this, [this, local, remote]() {
            qDebug() << "[LKProxy] remote disconnected";
            if (m_proxyLocal2Remote.contains(local)) {
                m_proxyLocal2Remote.remove(local);
                local->close();
                local->deleteLater();
            }
            remote->deleteLater();
        });

        connect(remote, &QWebSocket::errorOccurred, this,
                [remote](QAbstractSocket::SocketError err) {
            qWarning() << "[LKProxy] remote socket error:" << err << remote->errorString();
        });

        remote->open(remoteUrl);
    });

    qDebug() << "[LKProxy] Listening on ws://localhost:" << localPort
             << "→" << realWsBaseUrl;
    return true;
}

void WxBridge::stopLivekitProxy()
{
    if (m_wsProxyServer) {
        m_wsProxyServer->close();
        // 关闭所有代理连接
        for (auto it = m_proxyLocal2Remote.begin(); it != m_proxyLocal2Remote.end(); ++it) {
            it.key()->close();
            it.value()->close();
            it.value()->deleteLater();
            it.key()->deleteLater();
        }
        m_proxyLocal2Remote.clear();
        delete m_wsProxyServer;
        m_wsProxyServer = nullptr;
        qDebug() << "[LKProxy] stopped";
    }
}

