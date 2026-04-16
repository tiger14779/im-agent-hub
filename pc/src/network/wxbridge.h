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
#include <QWebSocketServer>
#include <QWebSocket>
#include <QtQml/qqmlregistration.h>

/**
 * @brief 财务软件桥接器 —— 通过 HTTP API 与外部财务/记账软件交互
 *
 * 工作原理：
 *   - 在端口 8888 启动 HTTP 服务，接收财务软件发来的指令（发消息/获取好友列表等）
 *   - 通过 HTTP POST 到端口 7888 推送消息事件和好友列表给财务软件
 * 注册为 QML 单例，在 QML 中可直接通过 WxBridge 访问。
 */
class WxBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // 服务是否正在监听
    Q_PROPERTY(bool listening READ isListening NOTIFY listeningChanged)

public:
    explicit WxBridge(QObject *parent = nullptr);
    ~WxBridge();

    bool isListening() const { return m_listening; }

    // 在端口 8888 启动 HTTP API 服务
    Q_INVOKABLE bool startServer();
    // 停止 HTTP API 服务
    Q_INVOKABLE void stopServer();

    // 推送消息事件到财务软件（端口 7888）
    // isSelf: true = 本机发送, false = 接收到的消息
    Q_INVOKABLE void pushMessageEvent(const QString &fromId, const QString &toId,
                                       const QString &msg, bool isSelf, int wxType = 1);
    // 推送好友列表到财务软件（端口 7888）
    Q_INVOKABLE void pushFriendList(const QJsonArray &contacts);

    // LiveKit 信令代理：在 localPort 监听，将 WebSocket 流量转发到 realWsBaseUrl
    // 用于绕开 QtWebEngine Chromium 的 TLS 兼容问题（用 Qt/Schannel 处理 SSL）
    Q_INVOKABLE bool startLivekitProxy(const QString &realWsBaseUrl, quint16 localPort = 8889);
    Q_INVOKABLE void stopLivekitProxy();

signals:
    void listeningChanged();  // 监听状态变化

    // ── 财务软件下发的 API 指令 ──
    // type: Q0001(文本), Q0011(图片), Q0030(文件), Q0005(获取好友列表)
    void apiSendText(const QString &wxid, const QString &msg);   // 发送文本消息
    void apiSendImage(const QString &wxid, const QString &path);  // 发送图片
    void apiSendFile(const QString &wxid, const QString &path);   // 发送文件
    void apiGetFriendList();                                      // 获取好友列表

    void bridgeError(const QString &error);  // 桥接器错误

private slots:
    void onNewConnection();  // 新的客户端连接到 API 服务

private:
    // 解析并处理财务软件发来的 API 请求
    void handleApiRequest(const QString &body, QTcpSocket *socket);
    // 通过 HTTP POST 推送数据到财务软件回调地址
    void pushToCallback(const QJsonObject &payload);

    QTcpServer *m_server = nullptr;        // TCP 服务器实例
    QNetworkAccessManager m_nam;           // 用于推送数据的网络管理器
    QHash<QTcpSocket*, QByteArray> m_buffers; // 各连接的接收缓冲区
    QHash<QString, qint64> m_recentCommands;  // 去重：type+wxid+path → 时间戳（5秒窗口）

    // LiveKit 信令代理
    QWebSocketServer *m_wsProxyServer = nullptr;
    QString m_livekitBaseWsUrl;                        // 真实 LiveKit wss:// 地址
    QHash<QWebSocket*, QWebSocket*> m_proxyLocal2Remote; // 本地 socket → 远程 socket

    bool m_listening = false;
    static constexpr int m_apiPort = 8888;       // 监听端口：接收财务软件指令
    static constexpr int m_callbackPort = 7888;   // 回调端口：推送事件给财务软件
};

#endif // WXBRIDGE_H
