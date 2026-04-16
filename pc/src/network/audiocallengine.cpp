#include "audiocallengine.h"

#include <QDebug>
#include <QUrl>
#include <cmath>

// ── AudioCallEngine ──────────────────────────────────────────────────────────

AudioCallEngine::AudioCallEngine(QObject *parent)
    : QObject(parent)
{
    // WebSocket 信号
    connect(&m_ws, &QWebSocket::connected,    this, &AudioCallEngine::onWsConnected);
    connect(&m_ws, &QWebSocket::disconnected, this, &AudioCallEngine::onWsDisconnected);
    connect(&m_ws, &QWebSocket::binaryMessageReceived, this, &AudioCallEngine::onAudioFrame);
    connect(&m_ws, QOverload<QAbstractSocket::SocketError>::of(&QWebSocket::errorOccurred),
            this, &AudioCallEngine::onWsError);
}

AudioCallEngine::~AudioCallEngine()
{
    stop();
}

// ── static helpers ────────────────────────────────────────────────────────────

QAudioFormat AudioCallEngine::audioFormat()
{
    QAudioFormat fmt;
    fmt.setSampleRate(8000);
    fmt.setChannelCount(1);
    fmt.setSampleFormat(QAudioFormat::Int16);
    return fmt;
}

qint16 AudioCallEngine::rms(const QByteArray &pcm16)
{
    if (pcm16.size() < 2) return 0;
    const auto *samples = reinterpret_cast<const qint16 *>(pcm16.constData());
    int count = pcm16.size() / 2;
    double sum = 0.0;
    for (int i = 0; i < count; ++i) {
        double v = samples[i];
        sum += v * v;
    }
    return static_cast<qint16>(std::sqrt(sum / count));
}

QString AudioCallEngine::buildUrl(const QString &wsBase, const QString &serverBaseUrl,
                                  const QString &roomId, const QString &token)
{
    QString base = wsBase;
    if (base.isEmpty()) {
        // 自中继：将主服务器 http(s):// 转换为 ws(s)://
        base = serverBaseUrl;
        base.replace(QStringLiteral("https://"), QStringLiteral("wss://"));
        base.replace(QStringLiteral("http://"),  QStringLiteral("ws://"));
        // 去掉末尾斜杠
        if (base.endsWith(QLatin1Char('/'))) base.chop(1);
        base += QStringLiteral("/api/call/audio");
    }
    return QString(QStringLiteral("%1?roomId=%2&token=%3")).arg(base, roomId, token);
}

// ── 设备列表 ──────────────────────────────────────────────────────────────────

QStringList AudioCallEngine::inputDevices() const
{
    QStringList result;
    const auto devs = QMediaDevices::audioInputs();
    result.reserve(devs.size());
    for (const QAudioDevice &d : devs) {
        result << d.description();
    }
    return result;
}

QStringList AudioCallEngine::outputDevices() const
{
    QStringList result;
    const auto devs = QMediaDevices::audioOutputs();
    result.reserve(devs.size());
    for (const QAudioDevice &d : devs) {
        result << d.description();
    }
    return result;
}

// ── 通话控制 ──────────────────────────────────────────────────────────────────

void AudioCallEngine::start(const QString &wsBase, const QString &serverBaseUrl,
                             const QString &roomId, const QString &token,
                             const QString &inputId, const QString &outputId)
{
    if (m_active) stop();

    const QAudioFormat fmt = audioFormat();

    // 选择输入设备
    QAudioDevice inputDev = QMediaDevices::defaultAudioInput();
    if (!inputId.isEmpty()) {
        for (const QAudioDevice &d : QMediaDevices::audioInputs()) {
            if (d.id() == inputId.toUtf8()) { inputDev = d; break; }
        }
    }

    // 选择输出设备
    QAudioDevice outputDev = QMediaDevices::defaultAudioOutput();
    if (!outputId.isEmpty()) {
        for (const QAudioDevice &d : QMediaDevices::audioOutputs()) {
            if (d.id() == outputId.toUtf8()) { outputDev = d; break; }
        }
    }

    // 尝试用 8kHz 启动；若设备不支持则回退到设备首选格式（WASAPI 共享模式）
    QAudioFormat captureFormat = fmt;
    if (!inputDev.isFormatSupported(fmt)) {
        qDebug() << "[AudioCallEngine] 8kHz not supported by input, using preferred format";
        captureFormat = inputDev.preferredFormat();
    }
    QAudioFormat playbackFormat = fmt;
    if (!outputDev.isFormatSupported(fmt)) {
        qDebug() << "[AudioCallEngine] 8kHz not supported by output, using preferred format";
        playbackFormat = outputDev.preferredFormat();
    }

    // 启动音频采集
    m_source = new QAudioSource(inputDev, captureFormat, this);
    m_captureDevice = m_source->start();
    if (!m_captureDevice) {
        emit errorOccurred(QStringLiteral("麦克风启动失败"));
        delete m_source; m_source = nullptr;
        return;
    }
    connect(m_captureDevice, &QIODevice::readyRead, this, &AudioCallEngine::onCaptureReady);

    // 启动音频播放
    m_sink = new QAudioSink(outputDev, playbackFormat, this);
    m_playbackDevice = m_sink->start();
    if (!m_playbackDevice) {
        emit errorOccurred(QStringLiteral("扬声器启动失败"));
        m_source->stop(); delete m_source; m_source = nullptr;
        delete m_sink; m_sink = nullptr;
        return;
    }

    // 连接 WebSocket
    const QString url = buildUrl(wsBase, serverBaseUrl, roomId, token);
    qDebug() << "[AudioCallEngine] connecting to" << url;
    m_ws.open(QUrl(url));

    m_active = true;
    emit activeChanged();
}

void AudioCallEngine::stop()
{
    if (!m_active) return;

    m_ws.close();

    if (m_source) {
        m_source->stop();
        delete m_source;
        m_source = nullptr;
        m_captureDevice = nullptr;
    }
    if (m_sink) {
        m_sink->stop();
        delete m_sink;
        m_sink = nullptr;
        m_playbackDevice = nullptr;
    }

    m_active = false;
    emit activeChanged();
}

void AudioCallEngine::setMuted(bool muted)
{
    if (m_muted == muted) return;
    m_muted = muted;
    // 静音：将采集音量设为 0；取消静音：恢复 1.0
    if (m_source) {
        m_source->setVolume(muted ? 0.0f : 1.0f);
    }
    emit mutedChanged();
}

// ── 槽函数 ────────────────────────────────────────────────────────────────────

void AudioCallEngine::onWsConnected()
{
    qDebug() << "[AudioCallEngine] WebSocket connected";
}

void AudioCallEngine::onWsDisconnected()
{
    qDebug() << "[AudioCallEngine] WebSocket disconnected";
    // 对端断开 → 结束通话（不再主动重连）
    if (m_active) stop();
}

void AudioCallEngine::onWsError(QAbstractSocket::SocketError err)
{
    qDebug() << "[AudioCallEngine] WS error" << err << m_ws.errorString();
    emit errorOccurred(m_ws.errorString());
    if (m_active) stop();
}

void AudioCallEngine::onCaptureReady()
{
    if (!m_captureDevice || m_muted) {
        if (m_captureDevice) m_captureDevice->readAll(); // 丢弃静音帧
        return;
    }
    const QByteArray frame = m_captureDevice->readAll();
    if (!frame.isEmpty() && m_ws.state() == QAbstractSocket::ConnectedState) {
        m_ws.sendBinaryMessage(frame);
    }
}

void AudioCallEngine::onAudioFrame(const QByteArray &data)
{
    // 写入播放设备
    if (m_playbackDevice && !data.isEmpty()) {
        m_playbackDevice->write(data);
    }
    // 简单 VAD：RMS > 500 认为对端在说话
    emit peerSpeaking(rms(data) > 500);
}
