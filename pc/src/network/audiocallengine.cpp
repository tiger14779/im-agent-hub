#include "audiocallengine.h"

#include <QDebug>
#include <QUrl>
#include <QVector>
#include <QMutexLocker>
#include <cmath>
#include <cstring>

// ── AudioRingBuffer ──────────────────────────────────────────────────────────

AudioRingBuffer::AudioRingBuffer(QObject *parent)
    : QIODevice(parent)
{
    open(QIODevice::ReadOnly);
}

void AudioRingBuffer::push(const QByteArray &data)
{
    QMutexLocker lock(&m_mutex);
    // 缓冲过多时丢弃最旧的数据，防止延迟累积
    if (m_buf.size() + data.size() > kMaxBufBytes) {
        const int drop = m_buf.size() + data.size() - kMaxBufBytes;
        m_buf.remove(0, drop);
    }
    m_buf.append(data);
}

qint64 AudioRingBuffer::bytesAvailable() const
{
    QMutexLocker lock(&m_mutex);
    // 返回缓冲区内字节数 + QIODevice 基类的返回值
    // 即使缓冲为空也返回一个正数，让 sink 持续拉取（readData 会填静音）
    return qMax(static_cast<qint64>(m_buf.size()), static_cast<qint64>(4096))
           + QIODevice::bytesAvailable();
}

qint64 AudioRingBuffer::readData(char *data, qint64 maxSize)
{
    QMutexLocker lock(&m_mutex);
    if (m_buf.isEmpty()) {
        // 缓冲为空时填静音，避免爆音
        std::memset(data, 0, static_cast<size_t>(maxSize));
        return maxSize;
    }
    const qint64 n = qMin(maxSize, static_cast<qint64>(m_buf.size()));
    std::memcpy(data, m_buf.constData(), static_cast<size_t>(n));
    m_buf.remove(0, static_cast<int>(n));
    if (n < maxSize)
        std::memset(data + n, 0, static_cast<size_t>(maxSize - n));
    return maxSize; // 始终返回 maxSize，让 sink 以稳定速率运转
}

qint64 AudioRingBuffer::writeData(const char *, qint64)
{
    return 0; // 只读 device，不支持写
}

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
    fmt.setSampleRate(48000);  // 协议线上格式升级为 48kHz，无需降采样，消除混叠失真
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

// ── 格式转换辅助 ───────────────────────────────────────────────────────────────

static int bytesPerSample(QAudioFormat::SampleFormat fmt)
{
    switch (fmt) {
    case QAudioFormat::UInt8:  return 1;
    case QAudioFormat::Int16:  return 2;
    case QAudioFormat::Int32:  return 4;
    case QAudioFormat::Float:  return 4;
    default:                   return 0;
    }
}

static float decodeSample(const char *data, QAudioFormat::SampleFormat fmt)
{
    switch (fmt) {
    case QAudioFormat::UInt8:  return (*reinterpret_cast<const quint8 *>(data) - 128) / 128.0f;
    case QAudioFormat::Int16:  return *reinterpret_cast<const qint16 *>(data) / 32768.0f;
    case QAudioFormat::Int32:  return *reinterpret_cast<const qint32 *>(data) / 2147483648.0f;
    case QAudioFormat::Float:  return *reinterpret_cast<const float *>(data);
    default:                   return 0.0f;
    }
}

// 将任意采集格式 → 协议格式（8kHz Int16 单声道）
QByteArray AudioCallEngine::convertToWire(const QByteArray &raw, const QAudioFormat &src)
{
    const int srcRate = src.sampleRate();
    const int srcCh   = src.channelCount();
    const int bps     = bytesPerSample(src.sampleFormat());
    if (bps == 0 || srcCh == 0) return {};

    const int nSrcFrames = raw.size() / (bps * srcCh);
    if (nSrcFrames == 0) return {};

    const char *p = raw.constData();

    // 步骤1：解码并混合声道 → float 单声道
    QVector<float> mono(nSrcFrames);
    for (int i = 0; i < nSrcFrames; i++) {
        float sum = 0;
        for (int c = 0; c < srcCh; c++)
            sum += decodeSample(p + (i * srcCh + c) * bps, src.sampleFormat());
        mono[i] = (srcCh > 1) ? sum / srcCh : sum;
    }

    // 步骤2：均值框滤波降采样 srcRate → 8kHz
    // 对每个输出帧，将对应的全部输入样本求均值，
    // 相当于一个简单的低通（抗混叠）滤波器，消除混叠失真。
    const int dstRate    = 8000;
    const int nDstFrames = (srcRate == dstRate)
                           ? nSrcFrames
                           : static_cast<int>(static_cast<double>(nSrcFrames) * dstRate / srcRate);

    QByteArray out(nDstFrames * static_cast<int>(sizeof(qint16)), Qt::Uninitialized);
    qint16 *dst16 = reinterpret_cast<qint16 *>(out.data());

    if (srcRate == dstRate) {
        for (int i = 0; i < nDstFrames; i++)
            dst16[i] = static_cast<qint16>(qBound(-32768.0f, mono[i] * 32767.0f, 32767.0f));
    } else {
        const double ratio = static_cast<double>(srcRate) / dstRate; // e.g. 6.0 for 48k→8k
        for (int i = 0; i < nDstFrames; i++) {
            // 对应的源帧范围 [srcStart, srcEnd)
            const double srcStart = i * ratio;
            const double srcEnd   = srcStart + ratio;
            const int    si0      = static_cast<int>(srcStart);
            const int    si1      = qMin(static_cast<int>(std::ceil(srcEnd)), nSrcFrames);
            // 对窗口内所有源样本求均值（box filter = 简单低通滤波器）
            float sum   = 0;
            int   count = si1 - si0;
            for (int j = si0; j < si1; j++)
                sum += mono[j];
            const float sample = (count > 0) ? sum / count : 0.0f;
            dst16[i] = static_cast<qint16>(qBound(-32768.0f, sample * 32767.0f, 32767.0f));
        }
    }
    return out;
}

// 将协议格式（8kHz Int16 单声道）→ 任意播放格式
QByteArray AudioCallEngine::convertFromWire(const QByteArray &wire, const QAudioFormat &dst)
{
    const int srcRate    = 8000;
    const int nSrcFrames = wire.size() / static_cast<int>(sizeof(qint16));
    if (nSrcFrames == 0) return {};

    const qint16 *src16  = reinterpret_cast<const qint16 *>(wire.constData());
    const int dstRate    = dst.sampleRate();
    const int dstCh      = dst.channelCount();
    const int bps        = bytesPerSample(dst.sampleFormat());
    if (bps == 0 || dstCh == 0) return {};

    const int nDstFrames = (srcRate == dstRate)
                           ? nSrcFrames
                           : static_cast<int>(static_cast<double>(nSrcFrames) * dstRate / srcRate);

    QByteArray out(nDstFrames * dstCh * bps, Qt::Uninitialized);
    char *p = out.data();

    for (int i = 0; i < nDstFrames; i++) {
        // 线性插值
        float sample;
        if (srcRate == dstRate) {
            sample = src16[i] / 32768.0f;
        } else {
            const double srcIdx = static_cast<double>(i) * srcRate / dstRate;
            const int    si0    = static_cast<int>(srcIdx);
            const int    si1    = qMin(si0 + 1, nSrcFrames - 1);
            const float  frac   = static_cast<float>(srcIdx - si0);
            sample = src16[si0] / 32768.0f * (1.0f - frac) + src16[si1] / 32768.0f * frac;
        }
        sample = qBound(-1.0f, sample, 1.0f);

        // 编码到目标格式，写入所有声道
        for (int c = 0; c < dstCh; c++) {
            char *sp = p + (i * dstCh + c) * bps;
            switch (dst.sampleFormat()) {
            case QAudioFormat::UInt8:
                *reinterpret_cast<quint8 *>(sp) = static_cast<quint8>(sample * 127.0f + 128.0f);
                break;
            case QAudioFormat::Int16:
                *reinterpret_cast<qint16 *>(sp) = static_cast<qint16>(sample * 32767.0f);
                break;
            case QAudioFormat::Int32:
                *reinterpret_cast<qint32 *>(sp) = static_cast<qint32>(sample * 2147483647.0f);
                break;
            case QAudioFormat::Float:
                *reinterpret_cast<float *>(sp) = sample;
                break;
            default:
                break;
            }
        }
    }
    return out;
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
    // 保存实际使用的格式（可能与协议线上格式不同）
    m_captureFormat  = captureFormat;
    m_playbackFormat = playbackFormat;
    qDebug() << "[AudioCallEngine] capture format:"
             << captureFormat.sampleRate() << "Hz"
             << captureFormat.channelCount() << "ch"
             << captureFormat.sampleFormat();
    qDebug() << "[AudioCallEngine] playback format:"
             << playbackFormat.sampleRate() << "Hz"
             << playbackFormat.channelCount() << "ch"
             << playbackFormat.sampleFormat();

    // 启动音频采集
    m_source = new QAudioSource(inputDev, captureFormat, this);
    m_captureDevice = m_source->start();
    if (!m_captureDevice) {
        emit errorOccurred(QStringLiteral("麦克风启动失败"));
        delete m_source; m_source = nullptr;
        return;
    }
    connect(m_captureDevice, &QIODevice::readyRead, this, &AudioCallEngine::onCaptureReady);

    // 启动音频播放（pull 模式：sink 主动从环形缓冲区拉数据，避免 push 模式下的缓冲堆积/爆音）
    m_ringBuffer = new AudioRingBuffer(this);
    m_sink = new QAudioSink(outputDev, playbackFormat, this);
    // 设置合适的缓冲大小：约 80ms，减少延迟
    const int bufBytes = static_cast<int>(playbackFormat.sampleRate()
                                          * playbackFormat.channelCount()
                                          * bytesPerSample(playbackFormat.sampleFormat())
                                          * 0.08); // 80ms
    if (bufBytes > 0) m_sink->setBufferSize(bufBytes);
    m_sink->start(m_ringBuffer); // pull 模式：传入 QIODevice*

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

    // 先置 false，防止 m_ws.close() 同步触发 disconnected/error 信号导致递归调用 stop()
    m_active = false;

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
    }
    if (m_ringBuffer) {
        delete m_ringBuffer;
        m_ringBuffer = nullptr;
    }

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
    const QByteArray raw = m_captureDevice->readAll();
    if (raw.isEmpty() || m_ws.state() != QAbstractSocket::ConnectedState) return;

    // 如果采集格式已是协议格式（8kHz Int16 单声道）则直接发送；否则转换
    const QAudioFormat wire = audioFormat();
    if (m_captureFormat == wire) {
        m_ws.sendBinaryMessage(raw);
    } else {
        const QByteArray pcm16 = convertToWire(raw, m_captureFormat);
        if (!pcm16.isEmpty()) m_ws.sendBinaryMessage(pcm16);
    }
}

void AudioCallEngine::onAudioFrame(const QByteArray &data)
{
    // 简单 VAD：基于原始 8kHz Int16 数据计算 RMS
    emit peerSpeaking(rms(data) > 500);

    if (!m_ringBuffer || data.isEmpty()) return;

    // 转换后推入环形缓冲区（sink 以 pull 模式自行拉取）
    const QAudioFormat wire = audioFormat();
    if (m_playbackFormat == wire) {
        m_ringBuffer->push(data);
    } else {
        const QByteArray converted = convertFromWire(data, m_playbackFormat);
        if (!converted.isEmpty()) m_ringBuffer->push(converted);
    }
}
