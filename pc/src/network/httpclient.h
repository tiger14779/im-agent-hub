#ifndef HTTPCLIENT_H
#define HTTPCLIENT_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonObject>
#include <QJsonArray>
#include <QTemporaryDir>
#include <QSettings>
#include <QHash>
#include <QtQml/qqmlregistration.h>

class HttpClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString token READ token WRITE setToken NOTIFY tokenChanged)
    Q_PROPERTY(QString serviceUserId READ serviceUserId WRITE setServiceUserId NOTIFY serviceUserIdChanged)

public:
    explicit HttpClient(QObject *parent = nullptr);
    ~HttpClient() override;

    QString baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QString &url);

    QString token() const { return m_token; }
    void setToken(const QString &token);

    QString serviceUserId() const { return m_serviceUserId; }
    void setServiceUserId(const QString &id);

    // === Auth ===
    // Service staff login: POST /api/service/auth/login
    Q_INVOKABLE void login(const QString &userId);

    // === Contacts ===
    // GET /api/service/contacts
    Q_INVOKABLE void getContacts();
    // POST /api/service/contacts  (add user)
    Q_INVOKABLE void addContact(const QString &nickname, const QString &avatar);
    // PUT /api/service/contacts/:userId  (update nickname/avatar)
    Q_INVOKABLE void updateContact(const QString &userId, const QString &nickname, const QString &avatar);

    // === File upload ===
    Q_INVOKABLE void uploadFile(const QString &filePath);
    Q_INVOKABLE void uploadAvatar(const QString &filePath);

    // === File download ===
    // Download and open with system default application
    Q_INVOKABLE void downloadAndOpen(const QString &url, const QString &fileName);
    // Download to a specific save path
    Q_INVOKABLE void downloadToPath(const QString &url, const QString &savePath);

    // === Settings ===
    Q_INVOKABLE void saveLoginConfig(const QString &userId, const QString &serverUrl);
    Q_INVOKABLE QJsonObject loadLoginConfig();

signals:
    void baseUrlChanged();
    void tokenChanged();
    void serviceUserIdChanged();

    // Login
    void loginSuccess(const QJsonObject &data);
    void loginFailed(const QString &error);

    // Contacts
    void contactsLoaded(const QJsonArray &contacts);
    void contactAdded(const QJsonObject &contact);
    void contactUpdated(const QJsonObject &contact);
    void contactError(const QString &error);

    // Upload
    void uploadSuccess(const QString &url, const QString &fileName, qint64 fileSize);
    void uploadFailed(const QString &error);
    void avatarUploaded(const QString &url);

    // Download
    void downloadFinished(const QString &localPath);
    void downloadFailed(const QString &error);

private:
    void handleReply(QNetworkReply *reply,
                     std::function<void(const QJsonObject &)> onSuccess,
                     std::function<void(const QString &)> onError);
    QNetworkRequest authedRequest(const QString &path) const;

    QNetworkAccessManager m_nam;
    QString m_baseUrl;
    QString m_token;
    QString m_serviceUserId;
    QTemporaryDir m_tempDir;

    // Upload cache: key = "path|size|lastModified" → server URL
    QHash<QString, QString> m_uploadCache;
};

#endif // HTTPCLIENT_H
