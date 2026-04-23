#ifndef LOTTERYCLIENT_H
#define LOTTERYCLIENT_H

#include <QObject>
#include <QLocalSocket>
#include <QTimer>
#include <QByteArray>
#include <QString>
#include <QtQml/qqmlregistration.h>
#include <QQmlEngine>
#include <QJSEngine>

/**
 * @brief 彩票数据接收客户端 —— 通过 QLocalSocket 连接到外部彩票软件，
 *        每秒接收一行 JSON：{"倒计时":N,"期号":N,"未结算":F,"球号":"..."}
 *
 * 行为：
 *   - 启动后立即尝试连接命名管道 "WeixinLotteryIPC"。
 *   - 连接断开后每 3 秒自动重连，外部软件重新打开后会继续更新。
 *   - 解析每行 JSON 后通过属性变更通知 QML，UI 实时刷新。
 *   - 注册为 QML 单例 LotteryClient，可在 QML 中直接访问。
 */
class LotteryClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool   connected  READ connected  NOTIFY connectedChanged)
    Q_PROPERTY(qint64 issue      READ issue      NOTIFY dataChanged)   // 期号
    Q_PROPERTY(QString balls     READ balls      NOTIFY dataChanged)   // 球号字符串，如 "46318"
    Q_PROPERTY(double  unsettled READ unsettled  NOTIFY dataChanged)   // 未结算金额
    Q_PROPERTY(int    countdown  READ countdown  NOTIFY dataChanged)   // 倒计时秒数
    Q_PROPERTY(bool   hasData    READ hasData    NOTIFY dataChanged)   // 是否已收到过数据

public:
    explicit LotteryClient(QObject *parent = nullptr);
    ~LotteryClient() override;

    // 提供给 QML 单例工厂使用的全局实例（在 main 中提前创建以立即开始连接）
    static LotteryClient *instance();

    // QML 单例工厂：复用全局 instance，避免 QQmlEngine 接管所有权
    static LotteryClient *create(QQmlEngine *, QJSEngine *) {
        QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
        return instance();
    }

    bool    connected() const { return m_connected; }
    qint64  issue()     const { return m_issue; }
    QString balls()     const { return m_balls; }
    double  unsettled() const { return m_unsettled; }
    int     countdown() const { return m_countdown; }
    bool    hasData()   const { return m_hasData; }

    // 启动连接（幂等，可由 QML 调用以确保连接已开始）
    Q_INVOKABLE void start();

signals:
    void connectedChanged();
    void dataChanged();

private slots:
    void onReadyRead();
    void onConnected();
    void onDisconnected();
    void onError(QLocalSocket::LocalSocketError);
    void tryConnect();

private:
    QLocalSocket *m_socket = nullptr;
    QTimer       *m_reconnectTimer = nullptr;
    QByteArray    m_buffer;

    bool    m_connected = false;
    bool    m_hasData   = false;
    qint64  m_issue     = 0;
    QString m_balls;
    double  m_unsettled = 0.0;
    int     m_countdown = 0;
};

#endif // LOTTERYCLIENT_H
