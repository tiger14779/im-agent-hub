#include "lotteryclient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

static const char *kPipeName = "WeixinLotteryIPC";

LotteryClient *LotteryClient::instance()
{
    static LotteryClient *s_inst = nullptr;
    if (!s_inst) {
        s_inst = new LotteryClient();
    }
    return s_inst;
}

LotteryClient::LotteryClient(QObject *parent)
    : QObject(parent)
{
    m_socket = new QLocalSocket(this);
    connect(m_socket, &QLocalSocket::readyRead,    this, &LotteryClient::onReadyRead);
    connect(m_socket, &QLocalSocket::connected,    this, &LotteryClient::onConnected);
    connect(m_socket, &QLocalSocket::disconnected, this, &LotteryClient::onDisconnected);
    connect(m_socket, &QLocalSocket::errorOccurred,this, &LotteryClient::onError);

    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setInterval(3000);
    m_reconnectTimer->setSingleShot(false);
    connect(m_reconnectTimer, &QTimer::timeout, this, &LotteryClient::tryConnect);

    // 构造时自动开始连接
    QMetaObject::invokeMethod(this, &LotteryClient::start, Qt::QueuedConnection);
}

LotteryClient::~LotteryClient()
{
    if (m_socket) {
        m_socket->disconnect(this);
        m_socket->abort();
    }
}

void LotteryClient::start()
{
    if (!m_reconnectTimer->isActive())
        m_reconnectTimer->start();
    tryConnect();
}

void LotteryClient::tryConnect()
{
    if (!m_socket) return;
    auto state = m_socket->state();
    if (state == QLocalSocket::ConnectedState || state == QLocalSocket::ConnectingState)
        return;
    m_socket->abort();
    m_buffer.clear();
    qDebug() << "[LotteryClient] try connect to pipe:" << kPipeName
             << "(full Win path: \\\\.\\pipe\\" << kPipeName << ")";
    m_socket->connectToServer(QString::fromLatin1(kPipeName));
}

void LotteryClient::onConnected()
{
    if (m_connected) return;
    m_connected = true;
    emit connectedChanged();
    qDebug() << "[LotteryClient] connected to" << kPipeName;
}

void LotteryClient::onDisconnected()
{
    if (!m_connected && !m_hasData) {
        // already disconnected, just ensure reconnect timer is running
    }
    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
        qDebug() << "[LotteryClient] disconnected from" << kPipeName;
    }
    m_buffer.clear();
    if (m_reconnectTimer && !m_reconnectTimer->isActive())
        m_reconnectTimer->start();
}

void LotteryClient::onError(QLocalSocket::LocalSocketError err)
{
    static QLocalSocket::LocalSocketError lastErr = static_cast<QLocalSocket::LocalSocketError>(-1);
    if (err != lastErr) {
        lastErr = err;
        qWarning() << "[LotteryClient] socket error:" << err
                   << "msg:" << (m_socket ? m_socket->errorString() : QString())
                   << "pipe:" << kPipeName;
    }
    if (m_connected) {
        m_connected = false;
        emit connectedChanged();
    }
    if (m_reconnectTimer && !m_reconnectTimer->isActive())
        m_reconnectTimer->start();
}

void LotteryClient::onReadyRead()
{
    m_buffer.append(m_socket->readAll());
    int newlineIdx;
    while ((newlineIdx = m_buffer.indexOf('\n')) >= 0) {
        QByteArray line = m_buffer.left(newlineIdx).trimmed();
        m_buffer.remove(0, newlineIdx + 1);
        if (line.isEmpty()) continue;

        QJsonParseError perr;
        QJsonDocument doc = QJsonDocument::fromJson(line, &perr);
        if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
            qWarning() << "[LotteryClient] bad JSON:" << perr.errorString() << line;
            continue;
        }
        QJsonObject obj = doc.object();

        const qint64 issue     = static_cast<qint64>(obj.value(QStringLiteral("期号")).toDouble());
        const QString balls    = obj.value(QStringLiteral("球号")).toString();
        const double  unsettled= obj.value(QStringLiteral("未结算")).toDouble();
        const int     countdown= obj.value(QStringLiteral("倒计时")).toInt();

        bool changed = false;
        if (issue != m_issue)        { m_issue = issue;       changed = true; }
        if (balls != m_balls)        { m_balls = balls;       changed = true; }
        if (!qFuzzyCompare(unsettled + 1.0, m_unsettled + 1.0)) {
            m_unsettled = unsettled; changed = true;
        }
        if (countdown != m_countdown){ m_countdown = countdown; changed = true; }
        if (!m_hasData)              { m_hasData = true;       changed = true; }

        if (changed)
            emit dataChanged();
    }
}
