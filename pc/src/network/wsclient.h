#ifndef WSCLIENT_H
#define WSCLIENT_H

#include <QObject>
#include <QWebSocket>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class WsClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

public:
    explicit WsClient(QObject *parent = nullptr);
    ~WsClient() override;

    bool isConnected() const { return m_connected; }

    // Connect to Go backend WebSocket:  ws://<host>/api/service/ws?staffId=xxx&token=xxx
    Q_INVOKABLE void connectToServer(const QString &baseUrl, const QString &staffId, const QString &token);
    Q_INVOKABLE void disconnect();

    // Send a chat message via the WS relay
    Q_INVOKABLE void sendMessage(const QString &recvId, int contentType,
                                  const QString &content, const QString &clientMsgId);

    // Request message history for a peer
    Q_INVOKABLE void loadHistory(const QString &peerUserId);

signals:
    void connectedChanged();
    // Incoming message from another user (via OpenIM poll)
    void newMessage(const QJsonObject &message);
    // Ack for a sent message
    void messageAck(const QString &clientMsgId, int status, const QString &serverMsgId, qint64 sendTime);
    // Message history loaded
    void historyLoaded(const QString &peerUserId, const QJsonArray &messages);
    // Contacts list changed on server
    void contactsUpdated();
    // Connection error
    void connectionError(const QString &error);

private slots:
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &message);
    void onError(QAbstractSocket::SocketError error);
    void tryReconnect();

private:
    void handleWsMessage(const QJsonObject &envelope);

    QWebSocket m_ws;
    QTimer m_reconnectTimer;
    QString m_baseUrl;
    QString m_staffId;
    QString m_token;
    bool m_connected = false;
    int m_reconnectAttempts = 0;
};

#endif // WSCLIENT_H
