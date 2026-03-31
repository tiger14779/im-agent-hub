#ifndef WSCLIENT_H
#define WSCLIENT_H

#include <QObject>
#include <QWebSocket>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QMap>
#include <QDateTime>
#include <QtQml/qqmlregistration.h>

/**
 * @brief WebSocket 客户端 —— 与 Go 后端保持长连接，实时收发消息
 *
 * 功能包括：连接服务器、发送聊天消息、加载历史记录、断线自动重连。
 * 注册为 QML 单例，在 QML 中可直接通过 WsClient 访问。
 */
class WsClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // 当前是否已连接到服务器
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

public:
    explicit WsClient(QObject *parent = nullptr);
    ~WsClient() override;

    bool isConnected() const { return m_connected; }

    // 连接到 Go 后端 WebSocket:  ws://<host>/api/service/ws?staffId=xxx&token=xxx
    Q_INVOKABLE void connectToServer(const QString &baseUrl, const QString &staffId, const QString &token);
    // 主动断开连接
    Q_INVOKABLE void disconnect();

    // 通过 WS 发送聊天消息（由服务端转发到 OpenIM）
    Q_INVOKABLE void sendMessage(const QString &recvId, int contentType,
                                  const QString &content, const QString &clientMsgId);

    // 加载与某个用户的历史聊天记录（支持分页）
    Q_INVOKABLE void loadHistory(const QString &peerUserId, qint64 beforeSeq = 0, int limit = 50);

    // 删除消息（通过 serverMsgId）
    Q_INVOKABLE void deleteMessage(const QString &serverMsgId);

    // 查询当前所有在线的H5客户端
    Q_INVOKABLE void queryOnline();

signals:
    void connectedChanged();                                    // 连接状态变化
    // 收到其他用户发来的新消息（经 OpenIM 轮询获取）
    void newMessage(const QJsonObject &message);
    // 发送消息应答：服务端确认发送状态
    void messageAck(const QString &clientMsgId, int status, const QString &serverMsgId, qint64 sendTime);
    // 历史消息加载完成
    void historyLoaded(const QString &peerUserId, const QJsonArray &messages, bool hasMore);
    // 服务器端联系人列表发生变化
    void contactsUpdated();
    // 消息被对方删除
    void messageDeleted(const QString &serverMsgId);
    // H5客户端在线状态变化 (status: "online", "background", "offline")
    void clientOnlineStatus(const QString &userId, const QString &status);
    // 在线客户端列表响应
    void onlineListReceived(const QJsonArray &clients);
    // 连接错误
    void connectionError(const QString &error);

private slots:
    void onConnected();                                 // WS 连接成功
    void onDisconnected();                              // WS 断开连接
    void onTextMessageReceived(const QString &message);  // 收到文本消息
    void onError(QAbstractSocket::SocketError error);    // WS 错误
    void tryReconnect();                                // 尝试重新连接
    void sendPing();                                    // 发送心跳 ping

private:
    // 待发送消息结构体（支持断线重发）
    struct PendingSend {
        QString recvId;
        int contentType;
        QString content;
        QString clientMsgId;
        int retries = 0;
        qint64 sentAt = 0; // 最近一次发送的时间戳(ms)
    };

    static constexpr int ACK_TIMEOUT_MS = 8000;  // ACK 超时 8 秒
    static constexpr int MAX_RETRIES = 2;         // 最多重试 2 次

    // 解析服务器下发的 WS 消息信封（分发到对应信号）
    void handleWsMessage(const QJsonObject &envelope);
    // 内部发起 WS 连接（构造 URL 并 open）
    void doConnect();
    // 内部实际发送一条消息到 WS
    void doSendMessage(PendingSend &ps);
    // 重连后自动重发所有待发消息
    void flushPendingSends();
    // 定期检查 ACK 超时
    void checkAckTimeouts();

    QWebSocket m_ws;               // WebSocket 实例
    QTimer m_reconnectTimer;       // 重连定时器（断线后指数退避重连）
    QTimer m_pingTimer;            // 心跳定时器（每25秒发送 ping）
    QTimer m_ackCheckTimer;        // ACK 超时检查定时器（每2秒检查）
    QString m_baseUrl;             // 服务器基础地址，清空表示不再重连
    QString m_staffId;             // 客服人员ID
    QString m_token;               // 认证令牌
    bool m_connected = false;      // 当前连接状态
    int m_reconnectAttempts = 0;   // 已重连次数（用于指数退避计算）
    QMap<QString, PendingSend> m_pendingSends; // 待确认消息队列

    // 挂起的历史加载请求（断线时保存，重连后自动发送）
    QString m_pendingHistoryPeer;
    qint64 m_pendingHistorySeq = 0;
    int m_pendingHistoryLimit = 50;
};

#endif // WSCLIENT_H
