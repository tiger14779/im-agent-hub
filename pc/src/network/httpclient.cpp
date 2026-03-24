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

HttpClient::HttpClient(QObject *parent)
    : QObject(parent)
{
}

HttpClient::~HttpClient()
{
    // Abort all pending network replies to prevent [this] lambda callbacks
    // from firing after destruction
    const auto replies = findChildren<QNetworkReply*>();
    for (QNetworkReply *reply : replies) {
        reply->disconnect();   // detach finished signal
        reply->abort();
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

// ── Auth ────────────────────────────────────────────────

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

// ── Contacts ────────────────────────────────────────────

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

void HttpClient::addContact(const QString &nickname, const QString &avatar)
{
    QNetworkRequest req = authedRequest("/api/service/contacts");
    QJsonObject body;
    body["nickname"] = nickname;
    if (!avatar.isEmpty()) body["avatar"] = avatar;

    QNetworkReply *reply = m_nam.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit contactAdded(resp["data"].toObject());
        },
        [this](const QString &err) { emit contactError(err); });
}

void HttpClient::updateContact(const QString &userId, const QString &nickname, const QString &avatar)
{
    QNetworkRequest req = authedRequest("/api/service/contacts/" + userId);
    QJsonObject body;
    if (!nickname.isEmpty()) body["nickname"] = nickname;
    if (!avatar.isEmpty()) body["avatar"] = avatar;

    QNetworkReply *reply = m_nam.put(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    handleReply(reply,
        [this](const QJsonObject &resp) {
            emit contactUpdated(resp["data"].toObject());
        },
        [this](const QString &err) { emit contactError(err); });
}

// ── File Upload ─────────────────────────────────────────

void HttpClient::uploadFile(const QString &filePath)
{
    QString localPath = filePath;
    if (localPath.startsWith("file:///"))
        localPath = QUrl(localPath).toLocalFile();

    QFileInfo fi(localPath);
    QString origName = fi.fileName();
    qint64 origSize = fi.size();

    // Check upload cache: same file (path + size + mtime) → reuse URL
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

// ── Settings ─────────────────────────────────────────────

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

// ── File Download ────────────────────────────────────────

void HttpClient::downloadAndOpen(const QString &url, const QString &fileName)
{
    if (url.isEmpty()) {
        emit downloadFailed("下载链接为空");
        return;
    }

    // Resolve relative URL
    QString fullUrl = url;
    if (url.startsWith('/'))
        fullUrl = m_baseUrl + url;

    // Save to temp directory with original file name
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

        // Open with system default application
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

    // Resolve relative URL
    QString fullUrl = url;
    if (url.startsWith('/'))
        fullUrl = m_baseUrl + url;

    // Ensure target directory exists
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

// ── Internal ────────────────────────────────────────────

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
