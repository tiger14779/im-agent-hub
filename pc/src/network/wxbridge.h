#ifndef WXBRIDGE_H
#define WXBRIDGE_H

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonObject>
#include <QJsonArray>
#include <QHash>
#include <QtQml/qqmlregistration.h>

class WxBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool listening READ isListening NOTIFY listeningChanged)

public:
    explicit WxBridge(QObject *parent = nullptr);
    ~WxBridge();

    bool isListening() const { return m_listening; }

    // Start HTTP API server on port 8888
    Q_INVOKABLE bool startServer();
    Q_INVOKABLE void stopServer();

    // Push a message event to the accounting software on port 7888
    // isSelf: true = sent by this PC, false = received from others
    Q_INVOKABLE void pushMessageEvent(const QString &fromId, const QString &toId,
                                       const QString &msg, bool isSelf, int wxType = 1);
    // Push friend list to accounting software on port 7888
    Q_INVOKABLE void pushFriendList(const QJsonArray &contacts);

signals:
    void listeningChanged();

    // Incoming API command from accounting software
    // type: Q0001(text), Q0011(image), Q0030(file), Q0005(friendList)
    void apiSendText(const QString &wxid, const QString &msg);
    void apiSendImage(const QString &wxid, const QString &path);
    void apiSendFile(const QString &wxid, const QString &path);
    void apiGetFriendList();

    void bridgeError(const QString &error);

private slots:
    void onNewConnection();

private:
    void handleApiRequest(const QString &body, QTcpSocket *socket);
    void pushToCallback(const QJsonObject &payload);

    QTcpServer *m_server = nullptr;
    QNetworkAccessManager m_nam;
    QHash<QTcpSocket*, QByteArray> m_buffers;

    bool m_listening = false;
    static constexpr int m_apiPort = 8888;       // listen for commands
    static constexpr int m_callbackPort = 7888;   // push events to
};

#endif // WXBRIDGE_H
