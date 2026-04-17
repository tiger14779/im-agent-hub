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

void AudioRingBuffer::clear()
{
    QMutexLocker lock(&m_mutex);
    m_buf.clear();
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

    // Sink 看门狗：每 300ms 检出 Realtek 等驱动把 sink 置大 Stopped/Suspended 的情况
    m_sinkWatchdog = new QTimer(this);
    m_sinkWatchdog->setInterval(300);
    connect(m_sinkWatchdog, &QTimer::timeout, this, &AudioCallEngine::onSinkWatchdog);
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

// 将任意采集格式 → 协议格式（Int16 单声道，采样率与 audioFormat() 一致）
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

    // 步骤2：重采样 srcRate → 线上格式采样率（与 audioFormat() 一致）
    // 对每个输出帧，将对应的全部输入样本求均值，
    // 相当于一个简单的低通（抗混叠）滤波器，消除混叠失真。
    const int dstRate    = audioFormat().sampleRate(); // 48000
    const int nDstFrames = (srcRate == dstRate)
                           ? nSrcFrames
                           : static_cast<int>(static_cast<double>(nSrcFrames) * dstRate / srcRate);

    QByteArray out(nDstFrames * static_cast<int>(sizeof(qint16)), Qt::Uninitialized);
    qint16 *dst16 = reinterpret_cast<qint16 *>(out.data());

    if (srcRate == dstRate) {
        for (int i = 0; i < nDstFrames; i++)
            dst16[i] = static_cast<qint16>(qBound(-32768.0f, mono[i] * 32767.0f, 32767.0f));
    } else {
        const double ratio = static_cast<double>(srcRate) / dstRate;
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

// 将协议格式（Int16 单声道，采样率与 audioFormat() 一致）→ 任意播放格式
QByteArray AudioCallEngine::convertFromWire(const QByteArray &wire, const QAudioFormat &dst)
{
    const int srcRate    = audioFormat().sampleRate(); // 48000
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

QString AudioCallEngine::inputDeviceId(int index) const
{
    const auto devs = QMediaDevices::audioInputs();
    if (index < 0 || index >= devs.size()) return {};
    return QString::fromUtf8(devs.at(index).id());
}

QString AudioCallEngine::outputDeviceId(int index) const
{
    const auto devs = QMediaDevices::audioOutputs();
    if (index < 0 || index >= devs.size()) return {};
    return QString::fromUtf8(devs.at(index).id());
}

// WASAPI 部分设备（如虚拟麦克风、蓝牙设备）preferredFormat() 会返回无效格式
// （0 Hz / 0 ch / Unknown），需要回退到协议格式。
static QAudioFormat resolveInputFormat(const QAudioDevice &dev, const QAudioFormat &wireFormat)
{
    const QAudioFormat pref = dev.preferredFormat();
    if (pref.isValid() && pref.sampleRate() > 0 && pref.channelCount() > 0)
        return pref;
    qWarning() << "[AudioCallEngine] input preferredFormat invalid for" << dev.description()
               << ", falling back to wire format";
    return wireFormat; // 48kHz Int16 Mono
}

// 同理，输出设备格式回退
static QAudioFormat resolveOutputFormat(const QAudioDevice &dev, const QAudioFormat &wireFormat)
{
    const QAudioFormat pref = dev.preferredFormat();
    if (pref.isValid() && pref.sampleRate() > 0 && pref.channelCount() > 0)
        return pref;
    qWarning() << "[AudioCallEngine] output preferredFormat invalid for" << dev.description()
               << ", falling back to wire format";
    return wireFormat;
}

void AudioCallEngine::changeInputDevice(const QString &inputId)
{
    if (!m_active) return;

    QAudioDevice inputDev = QMediaDevices::defaultAudioInput();
    if (!inputId.isEmpty()) {
        for (const QAudioDevice &d : QMediaDevices::audioInputs()) {
            if (d.id() == inputId.toUtf8()) { inputDev = d; break; }
        }
    }

    // WASAPI 共享模式下 isFormatSupported() 不可靠（尤其 Realtek）
    // 始终使用设备首选格式，由 convertToWire 负责格式转换
    const QAudioFormat captureFormat = resolveInputFormat(inputDev, audioFormat());
    m_captureFormat = captureFormat;

    // 先断开旧信号，防止 stop() 内部处理事件时触发 onCaptureReady 重入
    if (m_captureDevice) {
        disconnect(m_captureDevice, &QIODevice::readyRead, this, &AudioCallEngine::onCaptureReady);
        m_captureDevice = nullptr;
    }
    if (m_source) {
        m_source->stop();
        m_source->deleteLater(); // 延迟删除，避免主线程等待 WASAPI 内部线程退出而卡死
        m_source = nullptr;
    }
    m_source = new QAudioSource(inputDev, captureFormat, this);
    if (m_muted) m_source->setVolume(0.0f);
    m_captureDevice = m_source->start();
    if (m_captureDevice)
        connect(m_captureDevice, &QIODevice::readyRead, this, &AudioCallEngine::onCaptureReady);
    qDebug() << "[AudioCallEngine] input device switched to" << inputDev.description();
}

void AudioCallEngine::changeOutputDevice(const QString &outputId)
{
    if (!m_active || !m_ringBuffer) return;

    QAudioDevice outputDev = QMediaDevices::defaultAudioOutput();
    if (!outputId.isEmpty()) {
        for (const QAudioDevice &d : QMediaDevices::audioOutputs()) {
            if (d.id() == outputId.toUtf8()) { outputDev = d; break; }
        }
    }

    // WASAPI 共享模式下 isFormatSupported() 不可靠（尤其 Realtek）
    // 始终使用设备首选格式，由 convertFromWire 负责格式转换
    const QAudioFormat playbackFormat = resolveOutputFormat(outputDev, audioFormat());
    m_playbackFormat = playbackFormat;

    if (m_sink) {
        m_sink->stop();
        m_sink->deleteLater(); // 延迟删除，避免主线程卡死
        m_sink = nullptr;
    }

    // 清空环形缓冲，避免旧设备格式的残留数据在新设备上播放乱码
    m_ringBuffer->clear();

    m_sink = new QAudioSink(outputDev, playbackFormat, this);
    const int bufBytes = static_cast<int>(playbackFormat.sampleRate()
                                          * playbackFormat.channelCount()
                                          * bytesPerSample(playbackFormat.sampleFormat())
                                          * 0.08);
    if (bufBytes > 0) m_sink->setBufferSize(bufBytes);
    m_sink->start(m_ringBuffer);
    qDebug() << "[AudioCallEngine] output device switched to" << outputDev.description();
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

    // WASAPI 共享模式下 isFormatSupported() 对部分设备（如 Realtek）不可靠：
    // 有时报告支持某格式但实际静默丢包。始终使用 preferredFormat()，
    // convertToWire / convertFromWire 负责与协议格式（48kHz Int16 Mono）之间的转换。
    const QAudioFormat captureFormat  = resolveInputFormat(inputDev,   audioFormat());
    const QAudioFormat playbackFormat = resolveOutputFormat(outputDev, audioFormat());
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

    // 启动音频采集（失败时仅警告，不中断通话，仍可听到对方）
    m_source = new QAudioSource(inputDev, captureFormat, this);
    m_captureDevice = m_source->start();
    if (!m_captureDevice) {
        qWarning() << "[AudioCallEngine] microphone failed to start (format="
                   << captureFormat.sampleRate() << "Hz" << captureFormat.channelCount() << "ch"
                   << captureFormat.sampleFormat() << "), continuing without capture";
        delete m_source; m_source = nullptr;
        // 不 return：即使没有麦克风也要建立 sink 和 WS，让用户至少能听到对方
    } else {
        connect(m_captureDevice, &QIODevice::readyRead, this, &AudioCallEngine::onCaptureReady);
    }

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
    qDebug() << "[AudioCallEngine] sink started: state=" << m_sink->state()
             << "error=" << m_sink->error()
             << "fmt=" << playbackFormat.sampleRate() << "Hz"
             << playbackFormat.channelCount() << "ch" << playbackFormat.sampleFormat();
    m_sinkWatchdog->start();

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
    m_sinkWatchdog->stop();
    m_sinkIdleTicks = 0;

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

    // 清空 AEC 状态
    m_speakerRef.clear();
    m_nlmsW.clear();

    emit activeChanged();
}

void AudioCallEngine::setAecEnabled(bool enabled)
{
    if (m_aecEnabled == enabled) return;
    m_aecEnabled = enabled;
    if (!enabled) {
        // 关闭时重置过滤器状态
        m_speakerRef.clear();
        m_nlmsW.clear();
    }
    emit aecEnabledChanged();
    qDebug() << "[AudioCallEngine] AEC" << (enabled ? "enabled" : "disabled");
}

// ―― NLMS 自适应回声消除 ――――――――――――――――――――――――――――――――――――――――――――――――――――――
//
// 使用 NLMS 自适滤波器从麦克风信号中消除扪声器产生的回声。
// 输入： wire 格式的单声道 PCM16 48kHz
// 参考：m_speakerRef（扪声器历史播放数据）
// 输出：回声消除后的 PCM16
QByteArray AudioCallEngine::applyAec(const QByteArray &wirePcm16)
{
    const int n = wirePcm16.size() / 2;
    if (n == 0) return wirePcm16;

    const int refSize = m_speakerRef.size() / 2;  // 参考缓冲区样本数
    // 需要足够的参考数据才开始过滤（热启动期）
    if (refSize < kAecDelay + n + kAecTaps) return wirePcm16;

    if (static_cast<int>(m_nlmsW.size()) != kAecTaps)
        m_nlmsW.assign(kAecTaps, 0.0f);

    const qint16 *refData = reinterpret_cast<const qint16 *>(m_speakerRef.constData());
    const qint16 *micData = reinterpret_cast<const qint16 *>(wirePcm16.constData());

    QByteArray output(wirePcm16.size(), 0);
    qint16 *out = reinterpret_cast<qint16 *>(output.data());

    // 对于当前帧第 i 个样本，回声来自 kAecDelay 之前的参考链
    // refHead[i] = refSize - kAecDelay - n + i（对应最新的参考样本索引）
    for (int i = 0; i < n; i++) {
        const int refHead = refSize - kAecDelay - n + i; // 过滤器指向的最新参考样本
        const int refTail = refHead - kAecTaps + 1;     // 最旧参考样本
        if (refTail < 0) { out[i] = micData[i]; continue; } // 超界保护

        const qint16 *x = refData + refTail; // x[0]=最旧, x[kAecTaps-1]=最新

        // 计算回声估计并更新权重（平均功率 + NLMS 更新）
        float y = 0.0f, power = 0.0f;
        for (int j = 0; j < kAecTaps; j++) {
            const float xj = x[j] / 32768.0f;
            y     += m_nlmsW[j] * xj;
            power += xj * xj;
        }
        const float d  = micData[i] / 32768.0f;
        const float e  = d - y;  // 背景峥向信号（已消除回声）
        const float mu = kAecMu / (power + 1e-6f); // 归一化步长
        for (int j = 0; j < kAecTaps; j++) {
            m_nlmsW[j] += mu * e * (x[j] / 32768.0f);
        }
        out[i] = static_cast<qint16>(qBound(-32768.0f, e * 32768.0f, 32767.0f));
    }
    return output;
}

void AudioCallEngine::setMuted(bool muted)
{
    if (m_muted == muted) return;
    m_muted = muted;
    if (m_source)
        m_source->setVolume(muted ? 0.0f : 1.0f);
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

    // 统一转换为 wire 格式（Int16 48kHz 单声道）
    const QAudioFormat wire = audioFormat();
    QByteArray wirePcm16;
    if (m_captureFormat == wire) {
        wirePcm16 = raw;
    } else {
        wirePcm16 = convertToWire(raw, m_captureFormat);
        if (wirePcm16.isEmpty()) return;
    }

    // 应用回声消除（NLMS）
    if (m_aecEnabled)
        wirePcm16 = applyAec(wirePcm16);

    m_ws.sendBinaryMessage(wirePcm16);
}

void AudioCallEngine::onAudioFrame(const QByteArray &data)
{
    // 简单 VAD：基于原始 Int16 数据计算 RMS
    emit peerSpeaking(rms(data) > 500);

    if (!m_ringBuffer || data.isEmpty()) return;

    // 将 wire 格式数据保入 AEC 参考缓冲区（放音的历史信号）
    if (m_aecEnabled) {
        m_speakerRef.append(data);
        const int maxBytes = kAecRefMax * 2; // Int16 = 2 bytes/样本
        if (m_speakerRef.size() > maxBytes)
            m_speakerRef.remove(0, m_speakerRef.size() - maxBytes);
    }

    // 转换后推入环形缓冲区（sink 以 pull 模式自行拉取）
    const QAudioFormat wire = audioFormat();
    if (m_playbackFormat == wire) {
        m_ringBuffer->push(data);
    } else {
        const QByteArray converted = convertFromWire(data, m_playbackFormat);
        if (!converted.isEmpty()) m_ringBuffer->push(converted);
    }
}

// ── 来电铃声合成 ──────────────────────────────────────────────────────────────
// 铃声模式（循环 3400ms）：
//   0   – 650ms : 440Hz + 480Hz 双音（拍频 40Hz，经典电话铃感）
//   650 – 850ms : 静音
//   850 – 1500ms: 440Hz + 480Hz 双音（第二声）
//   1500– 3400ms: 静音

void AudioCallEngine::playRingtone()
{
    stopRingtone();

    QAudioFormat fmt;
    fmt.setSampleRate(44100);
    fmt.setChannelCount(1);
    fmt.setSampleFormat(QAudioFormat::Int16);

    m_ringtoneBuffer = new AudioRingBuffer(this);
    m_ringtoneSink   = new QAudioSink(QMediaDevices::defaultAudioOutput(), fmt, this);
    m_ringtoneSink->start(m_ringtoneBuffer);
    m_ringSamplePos  = 0;

    m_ringtoneTimer  = new QTimer(this);
    connect(m_ringtoneTimer, &QTimer::timeout, this, &AudioCallEngine::onRingtoneTick);
    m_ringtoneTimer->start(40);
    onRingtoneTick(); // 立即填充第一块
}

void AudioCallEngine::stopRingtone()
{
    if (m_ringtoneTimer) {
        m_ringtoneTimer->stop();
        delete m_ringtoneTimer;
        m_ringtoneTimer = nullptr;
    }
    if (m_ringtoneSink) {
        m_ringtoneSink->stop();
        delete m_ringtoneSink;
        m_ringtoneSink = nullptr;
    }
    if (m_ringtoneBuffer) {
        delete m_ringtoneBuffer;
        m_ringtoneBuffer = nullptr;
    }
    m_ringSamplePos = 0;
}

// ―― Sink 看门狗 ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
//
// Realtek 等驱动在 WASAPI 共享模式下三种静默无声情形：
//  1. StoppedState  → stop() 被驱动内部调用，需要重新 start()
//  2. SuspendedState→ 设备被系统挂起，需要 resume()
//  3. IdleState 持续超 1s → ring buffer 一直为空时 sink 进入 Idle，
//     此时驱动停止向硬件输出，数据到来后无法自动恢复（Realtek 特有行为）
//     → 送一帧静音数据 "唤醒" sink，使其重新进入 ActiveState
void AudioCallEngine::onSinkWatchdog()
{
    if (!m_active || !m_sink || !m_ringBuffer) return;
    const QAudio::State state = m_sink->state();
    const QAudio::Error err   = m_sink->error();

    if (state == QAudio::StoppedState) {
        qWarning() << "[Watchdog] sink Stopped err=" << err << ", restarting";
        m_sinkIdleTicks = 0;
        m_ringBuffer->clear();
        m_sink->start(m_ringBuffer);
    } else if (state == QAudio::SuspendedState) {
        qWarning() << "[Watchdog] sink Suspended, resuming";
        m_sinkIdleTicks = 0;
        m_sink->resume();
    } else if (state == QAudio::IdleState) {
        ++m_sinkIdleTicks;
        // IdleState 持续 > 1s（约 3 个 tick）且 ring buffer 有数据时，强制送一帧静音唤醒
        if (m_sinkIdleTicks >= 3) {
            qWarning() << "[Watchdog] sink stuck in Idle for" << (m_sinkIdleTicks * 300) << "ms, nudging";
            m_sinkIdleTicks = 0;
            // 送 20ms 静音推动 sink 从 Idle → Active
            const int silenceBytes = static_cast<int>(
                m_playbackFormat.sampleRate() * m_playbackFormat.channelCount()
                * bytesPerSample(m_playbackFormat.sampleFormat()) * 0.02f);
            if (silenceBytes > 0)
                m_ringBuffer->push(QByteArray(silenceBytes, 0));
        }
    } else {
        m_sinkIdleTicks = 0; // ActiveState → 正常，重置计数
    }
}

void AudioCallEngine::onRingtoneTick()
{
    if (!m_ringtoneBuffer) return;

    static constexpr int kSampleRate    = 44100;
    static constexpr int kChunkSamples  = kSampleRate * 40 / 1000;   // 40ms = 1764 samples
    static constexpr int kCycleSamples  = kSampleRate * 3400 / 1000; // 3400ms cycle
    static constexpr int kBurst1End     = kSampleRate * 650  / 1000;
    static constexpr int kBurst2Start   = kSampleRate * 850  / 1000;
    static constexpr int kBurst2End     = kSampleRate * 1500 / 1000;
    static constexpr int kFadeInSamples = kSampleRate * 25   / 1000;
    static constexpr int kFadeOutSamples= kSampleRate * 70   / 1000;

    QByteArray chunk(kChunkSamples * 2, 0);
    qint16 *out = reinterpret_cast<qint16 *>(chunk.data());

    for (int i = 0; i < kChunkSamples; ++i) {
        const int pos = (m_ringSamplePos + i) % kCycleSamples;

        int burstStart = -1, burstLen = 0;
        if (pos < kBurst1End) {
            burstStart = 0; burstLen = kBurst1End;
        } else if (pos >= kBurst2Start && pos < kBurst2End) {
            burstStart = kBurst2Start; burstLen = kBurst2End - kBurst2Start;
        }

        if (burstStart >= 0) {
            const double t = static_cast<double>(pos) / kSampleRate;
            double s = 0.22 * std::sin(2 * M_PI * 440.0 * t)
                     + 0.22 * std::sin(2 * M_PI * 480.0 * t);
            const int posInBurst = pos - burstStart;
            double env = 1.0;
            if (posInBurst < kFadeInSamples)
                env = static_cast<double>(posInBurst) / kFadeInSamples;
            else if (posInBurst > burstLen - kFadeOutSamples)
                env = qMax(0.0, static_cast<double>(burstLen - posInBurst) / kFadeOutSamples);
            out[i] = static_cast<qint16>(qBound(-32768.0, s * env * 32767.0, 32767.0));
        }
        // else: silence (already 0)
    }

    m_ringSamplePos = (m_ringSamplePos + kChunkSamples) % kCycleSamples;
    m_ringtoneBuffer->push(chunk);
}
