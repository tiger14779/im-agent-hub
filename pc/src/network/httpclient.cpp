#include "httpclient.h"

#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHttpMultiPart>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QDesktopServices>
#include <QDir>
#include <QUrl>
#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QImage>
#include <QUuid>
#include <QDateTime>
#include <QDrag>
#include <QWindow>

HttpClient::HttpClient(QObject *parent)
    : QObject(parent)
{
}

HttpClient::~HttpClient()
{
    // 销毁前中止所有未完成的网络请求，防止析构后 lambda 回调导致崩溃
    const auto replies = findChildren<QNetworkReply*>();
    for (QNetworkReply *reply : replies) {
        reply->disconnect();   // 断开 finished 信号
        reply->abort();        // 强制中止请求
        reply->deleteLater();
    }
}

void HttpClient::setBaseUrl(const QString &url)
{
    if (m_baseUrl != url) {
        m_baseUrl = url;
        emit baseUrlChanged();
    }
}

void HttpClient::setToken(const QString &token)
{
    if (m_token != token) {
        m_token = token;
        emit tokenChanged();
    }
}

void HttpClient::setServiceUserId(const QString &id)
{
    if (m_serviceUserId != id) {
        m_serviceUserId = id;
        emit serviceUserIdChanged();
    }
}

/**
 * @brief 构造带认证头的网络请求
 * 自动附加 Authorization 和 X-Service-UserID 请求头
 */
QNetworkRequest HttpClient::authedRequest(const QString &path) const
{
    QNetworkRequest req(QUrl(m_baseUrl + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    if (!m_token.isEmpty())
        req.setRawHeader("Authorization", m_token.toUtf8());
    if (!m_serviceUserId.isEmpty())
        req.setRawHeader("X-Service-UserID", m_serviceUserId.toUtf8());
    return req;
}

// ── 认证 ────────────────────────────────────────────────

void HttpClient::login(const QString &userId)
{
    QNetworkRequest req(QUrl(m_baseUrl + "/api/service/auth/login"));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject body;
    body["userId"] = userId;
    QByteArray data = QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkReply *reply = m_nam.post(req, data);
    handleReply(reply,
        [this](const QJsonObject &resp) {
            QJsonObject d = resp["data"].toObject();
            m_token = d["token"].toString();
            m_serviceUserId = d["userId"].toString();
            emit tokenChanged();
            emit serviceUserIdChanged();
            emit loginSuccess(d);
        },
        [this](const QString &err) { emit loginFailed(err); });
}

// ── 联系人管理 ──────────────────────────────────────────

void HttpClient::getContacts()
{
    QNetworkRequest req = authedRequest("/api/service/contacts");
    QNetworkReply *reply = m_nam.get(req);
    handleReply(reply,
        [this](const QJsonObject &resp) {
            QJsonArray arr = resp["data"].toArray();
            emit contactsLoaded(arr);
        },
        [this](const QString &err) { emit contactError(err); });
}

void HttpClient::addContact(const QString &nickname, const QString &groupNickname, const QString &avatar)
{
    QNetworkRequest req = authedRequest("/api/service/contacts");
    QJsonObject body;
    body["nickname"] = nickname;
    body["groupNickname"] = groupNickname;
    if (!avatar.isEmpty()) body["avatar"] = avatar;

    QNetworkReply *reply = m_nam.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit contactAdded(resp["data"].toObject());
        },
        [this](const QString &err) { emit contactError(err); });
}

void HttpClient::updateContact(const QString &userId, const QString &nickname, const QString &groupNickname, const QString &avatar)
{
    QNetworkRequest req = authedRequest("/api/service/contacts/" + userId);
    QJsonObject body;
    if (!nickname.isEmpty()) body["nickname"] = nickname;
    if (!groupNickname.isEmpty()) body["groupNickname"] = groupNickname;
    if (!avatar.isEmpty()) body["avatar"] = avatar;

    QNetworkReply *reply = m_nam.put(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit contactUpdated(resp["data"].toObject());
        },
        [this](const QString &err) { emit contactError(err); });
}

void HttpClient::getProfile()
{
    QNetworkRequest req = authedRequest("/api/service/profile");
    QNetworkReply *reply = m_nam.get(req);
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit profileUpdated(resp["data"].toObject());
        },
        [](const QString &err) { qWarning() << "[HttpClient] getProfile error:" << err; });
}

// ── 群组管理 ─────────────────────────────────────────────────────

void HttpClient::getGroups()
{
    QNetworkRequest req = authedRequest("/api/service/groups");
    QNetworkReply *reply = m_nam.get(req);
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit groupsLoaded(resp["data"].toObject()["list"].toArray());
        },
        [this](const QString &err) { emit groupError(err); });
}

void HttpClient::inviteToGroup(const QString &groupId, const QString &userId)
{
    QNetworkRequest req = authedRequest("/api/service/groups/" + groupId + "/members");
    QJsonObject body;
    body["userId"] = userId;
    QNetworkReply *reply = m_nam.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply,
        [this, groupId](const QJsonObject &) {
            emit groupMemberChanged(groupId);
        },
        [this](const QString &err) { emit groupError(err); });
}

void HttpClient::kickFromGroup(const QString &groupId, const QString &userId)
{
    QNetworkRequest req = authedRequest("/api/service/groups/" + groupId + "/members/" + userId);
    QNetworkReply *reply = m_nam.deleteResource(req);
    handleReply(reply,
        [this, groupId](const QJsonObject &) {
            emit groupMemberChanged(groupId);
        },
        [this](const QString &err) { emit groupError(err); });
}

void HttpClient::dissolveGroup(const QString &groupId)
{
    QNetworkRequest req = authedRequest("/api/service/groups/" + groupId);
    QNetworkReply *reply = m_nam.deleteResource(req);
    handleReply(reply,
        [this, groupId](const QJsonObject &) {
            emit groupMemberChanged(groupId);
        },
        [this](const QString &err) { emit groupError(err); });
}

void HttpClient::updateProfile(const QString &nickname, const QString &avatar)
{
    QNetworkRequest req = authedRequest("/api/service/profile");
    QJsonObject body;
    if (!nickname.isEmpty()) body["nickname"] = nickname;
    if (!avatar.isEmpty()) body["avatar"] = avatar;

    QNetworkReply *reply = m_nam.put(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit profileUpdated(resp["data"].toObject());
        },
        [](const QString &err) { qWarning() << "[HttpClient] updateProfile error:" << err; });
}

// ── 文件上传 ─────────────────────────────────────────────

void HttpClient::uploadFile(const QString &filePath)
{
    // 兼容 QML 传入的 file:/// 前缀路径
    QString localPath = filePath;
    if (localPath.startsWith("file:///"))
        localPath = QUrl(localPath).toLocalFile();

    QFileInfo fi(localPath);
    QString origName = fi.fileName();
    qint64 origSize = fi.size();
    qDebug() << "[Upload] path=" << localPath << "fileName=" << origName << "size=" << origSize;

    // 检查上传缓存：相同文件（路径+大小+修改时间）直接复用已上传的URL
    QString cacheKey = localPath + "|" + QString::number(origSize) + "|" + fi.lastModified().toString(Qt::ISODate);
    if (m_uploadCache.contains(cacheKey)) {
        emit uploadSuccess(m_uploadCache.value(cacheKey), origName, origSize);
        return;
    }

    QFile *file = new QFile(localPath);
    if (!file->open(QIODevice::ReadOnly)) {
        emit uploadFailed("无法打开文件: " + localPath);
        delete file;
        return;
    }

    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    QHttpPart filePart;
    QMimeDatabase mimeDb;
    QString mimeType = mimeDb.mimeTypeForFile(fi).name();

    filePart.setHeader(QNetworkRequest::ContentTypeHeader, mimeType);
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
        QString("form-data; name=\"file\"; filename=\"%1\"").arg(fi.fileName()));
    filePart.setBodyDevice(file);
    file->setParent(multiPart);
    multiPart->append(filePart);

    QNetworkRequest req(QUrl(m_baseUrl + "/api/upload"));
    QNetworkReply *reply = m_nam.post(req, multiPart);
    multiPart->setParent(reply);

    handleReply(reply,
        [this, origName, origSize, cacheKey](const QJsonObject &obj) {
            QString url = obj["data"].toObject()["url"].toString();
            if (url.isEmpty())
                emit uploadFailed("上传返回空URL");
            else {
                m_uploadCache.insert(cacheKey, url);
                emit uploadSuccess(url, origName, origSize);
            }
        },
        [this](const QString &err) { emit uploadFailed(err); });
}

// ── 头像上传 ─────────────────────────────────────────────

void HttpClient::uploadAvatar(const QString &filePath)
{
    QString localPath = filePath;
    if (localPath.startsWith("file:///"))
        localPath = QUrl(localPath).toLocalFile();

    QFile *file = new QFile(localPath);
    if (!file->open(QIODevice::ReadOnly)) {
        emit uploadFailed("无法打开文件: " + localPath);
        delete file;
        return;
    }

    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    QHttpPart filePart;
    QFileInfo fi(localPath);
    QMimeDatabase mimeDb;
    QString mimeType = mimeDb.mimeTypeForFile(fi).name();

    filePart.setHeader(QNetworkRequest::ContentTypeHeader, mimeType);
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
        QString("form-data; name=\"file\"; filename=\"%1\"").arg(fi.fileName()));
    filePart.setBodyDevice(file);
    file->setParent(multiPart);
    multiPart->append(filePart);

    QNetworkRequest req(QUrl(m_baseUrl + "/api/upload"));
    QNetworkReply *reply = m_nam.post(req, multiPart);
    multiPart->setParent(reply);

    handleReply(reply,
        [this](const QJsonObject &obj) {
            QString url = obj["data"].toObject()["url"].toString();
            if (url.isEmpty())
                emit uploadFailed("上传返回空URL");
            else
                emit avatarUploaded(url);
        },
        [this](const QString &err) { emit uploadFailed(err); });
}

// ── 登录配置持久化 ───────────────────────────────────

void HttpClient::saveLoginConfig(const QString &userId, const QString &serverUrl)
{
    QSettings settings;
    settings.setValue("login/userId", userId);
    settings.setValue("login/serverUrl", serverUrl);
}

QJsonObject HttpClient::loadLoginConfig()
{
    QSettings settings;
    QJsonObject obj;
    obj["userId"] = settings.value("login/userId", "").toString();
    obj["serverUrl"] = settings.value("login/serverUrl", "http://localhost:8080").toString();
    return obj;
}

void HttpClient::setSetting(const QString &key, const QString &value)
{
    QSettings settings;
    settings.setValue(key, value);
}

QString HttpClient::getSetting(const QString &key, const QString &defaultValue)
{
    QSettings settings;
    return settings.value(key, defaultValue).toString();
}

// ── 剪贴板操作 ─────────────────────────────────────────

void HttpClient::copyToClipboard(const QString &text)
{
    QGuiApplication::clipboard()->setText(text);
}

QJsonObject HttpClient::getClipboardContent()
{
    QJsonObject result;
    const QClipboard *clipboard = QGuiApplication::clipboard();
    const QMimeData *mime = clipboard->mimeData();

    if (!mime) {
        result["type"] = "none";
        return result;
    }

    // 优先检测图片
    if (mime->hasImage()) {
        result["type"] = "image";
        return result;
    }

    // 检测文件列表（从资源管理器复制的文件）
    if (mime->hasUrls()) {
        QList<QUrl> urls = mime->urls();
        QJsonArray paths;
        for (const QUrl &u : urls) {
            if (u.isLocalFile())
                paths.append(u.toLocalFile());
        }
        if (!paths.isEmpty()) {
            result["type"] = "file";
            result["paths"] = paths;
            return result;
        }
    }

    // 纯文本
    if (mime->hasText()) {
        result["type"] = "text";
        result["text"] = mime->text();
        return result;
    }

    result["type"] = "none";
    return result;
}

QString HttpClient::saveClipboardImage()
{
    const QClipboard *clipboard = QGuiApplication::clipboard();
    QImage image = clipboard->image();
    if (image.isNull())
        return {};

    // 生成唯一文件名保存到临时目录
    QString fileName = "clipboard_" + QUuid::createUuid().toString(QUuid::Id128).left(8) + ".png";
    QString savePath = m_tempDir.filePath(fileName);

    if (image.save(savePath, "PNG")) {
        qDebug() << "[Clipboard] saved image to" << savePath;
        return savePath;
    }
    return {};
}

void HttpClient::copyFileToClipboard(const QString &url, const QString &fileName)
{
    if (url.isEmpty()) return;

    QString fullUrl = url;
    if (url.startsWith('/'))
        fullUrl = m_baseUrl + url;

    QString saveName = fileName.isEmpty() ? "download" : fileName;
    QString savePath = m_tempDir.filePath(saveName);

    QNetworkRequest req{QUrl{fullUrl}};
    QNetworkReply *reply = m_nam.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[Clipboard] download failed:" << reply->errorString();
            return;
        }
        QFile file(savePath);
        if (!file.open(QIODevice::WriteOnly)) {
            qWarning() << "[Clipboard] cannot write:" << savePath;
            return;
        }
        file.write(reply->readAll());
        file.close();

        // 将本地文件路径设置到剪贴板
        QMimeData *mimeData = new QMimeData();
        mimeData->setUrls({QUrl::fromLocalFile(savePath)});
        QGuiApplication::clipboard()->setMimeData(mimeData);
        qDebug() << "[Clipboard] file copied:" << savePath;

        emit downloadFinished(savePath);
    });
}

void HttpClient::copyLinkAsFile(const QString &link)
{
    if (link.isEmpty()) return;

    // 在临时目录下创建 txt 子目录
    QString txtDir = m_tempDir.filePath("txt");
    QDir().mkpath(txtDir);

    QString filePath = txtDir + "/\u94FE\u63A5.txt";
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[Clipboard] cannot write link file:" << filePath;
        return;
    }
    file.write(link.toUtf8());
    file.close();

    // 将文件放到剪贴板
    QMimeData *mimeData = new QMimeData();
    mimeData->setUrls({QUrl::fromLocalFile(filePath)});
    QGuiApplication::clipboard()->setMimeData(mimeData);
    qDebug() << "[Clipboard] link file copied:" << filePath;
}

// ── 文件下载 ─────────────────────────────────────────────

void HttpClient::downloadAndOpen(const QString &url, const QString &fileName)
{
    if (url.isEmpty()) {
        emit downloadFailed("下载链接为空");
        return;
    }

    // 将相对URL拼接为完整地址
    QString fullUrl = url;
    if (url.startsWith('/'))
        fullUrl = m_baseUrl + url;

    // 保存到临时目录，使用原始文件名
    QString savePath = m_tempDir.filePath(fileName.isEmpty() ? "download" : fileName);

    QNetworkRequest req{QUrl{fullUrl}};
    QNetworkReply *reply = m_nam.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit downloadFailed(reply->errorString());
            return;
        }
        QFile file(savePath);
        if (!file.open(QIODevice::WriteOnly)) {
            emit downloadFailed("无法写入临时文件: " + savePath);
            return;
        }
        file.write(reply->readAll());
        file.close();

        // 使用系统默认应用打开已下载的文件
        QDesktopServices::openUrl(QUrl::fromLocalFile(savePath));
        emit downloadFinished(savePath);
    });
}

void HttpClient::downloadToPath(const QString &url, const QString &savePath)
{
    if (url.isEmpty() || savePath.isEmpty()) {
        emit downloadFailed("下载链接或保存路径为空");
        return;
    }

    // 将相对URL拼接为完整地址
    QString fullUrl = url;
    if (url.startsWith('/'))
        fullUrl = m_baseUrl + url;

    // 确保目标保存目录存在
    QFileInfo fi(savePath);
    QDir().mkpath(fi.absolutePath());

    QNetworkRequest req{QUrl{fullUrl}};
    QNetworkReply *reply = m_nam.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit downloadFailed(reply->errorString());
            return;
        }
        QFile file(savePath);
        if (!file.open(QIODevice::WriteOnly)) {
            emit downloadFailed("无法写入文件: " + savePath);
            return;
        }
        file.write(reply->readAll());
        file.close();

        emit downloadFinished(savePath);
    });
}

// ── 拖放操作 ─────────────────────────────────────────────

void HttpClient::startFileDrag(const QString &url, const QString &fileName)
{
    if (url.isEmpty()) return;

    QString fullUrl = url;
    if (url.startsWith('/'))
        fullUrl = m_baseUrl + url;

    QString saveName = fileName.isEmpty() ? "download" : fileName;
    QString savePath = m_tempDir.filePath(saveName);

    // 如果文件已缓存在本地，直接启动拖放
    if (QFile::exists(savePath)) {
        performDrag(savePath);
        return;
    }

    // 否则先下载到临时目录
    QNetworkRequest req{QUrl{fullUrl}};
    QNetworkReply *reply = m_nam.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, savePath]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[Drag] download failed:" << reply->errorString();
            return;
        }
        QFile file(savePath);
        if (!file.open(QIODevice::WriteOnly)) {
            qWarning() << "[Drag] cannot write:" << savePath;
            return;
        }
        file.write(reply->readAll());
        file.close();

        performDrag(savePath);
    });
}

void HttpClient::performDrag(const QString &localPath)
{
    auto *window = qobject_cast<QWindow*>(QGuiApplication::focusWindow());
    if (!window) return;

    QDrag *drag = new QDrag(window);
    QMimeData *mimeData = new QMimeData();
    mimeData->setUrls({QUrl::fromLocalFile(localPath)});
    drag->setMimeData(mimeData);
    drag->exec(Qt::CopyAction);
}

// ── 内部工具方法 ────────────────────────────────────────

void HttpClient::handleReply(QNetworkReply *reply,
    std::function<void(const QJsonObject &)> onSuccess,
    std::function<void(const QString &)> onError)
{
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            onError(reply->errorString());
            return;
        }
        QByteArray data = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isNull()) {
            onError("无效的JSON响应");
            return;
        }
        QJsonObject obj = doc.object();
        int code = obj["code"].toInt(-1);
        if (code != 0) {
            onError(obj["msg"].toString("未知错误"));
            return;
        }
        onSuccess(obj);
    });
}
