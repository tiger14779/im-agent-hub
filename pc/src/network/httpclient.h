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

/**
 * @brief HTTP 客户端 —— 负责与后端 REST API 通信
 *
 * 功能包括：登录认证、联系人管理、文件上传/下载、登录配置持久化。
 * 注册为 QML 单例，在 QML 中可直接通过 HttpClient 访问。
 */
class HttpClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // 服务器基础地址，例如 http://localhost:8080
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    // 登录后获取的 JWT token，用于后续接口鉴权
    Q_PROPERTY(QString token READ token WRITE setToken NOTIFY tokenChanged)
    // 当前客服人员的用户ID
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

    // === 认证 ===
    // 客服人员登录: POST /api/service/auth/login
    Q_INVOKABLE void login(const QString &userId);

    // === 联系人管理 ===
    // 获取联系人列表: GET /api/service/contacts
    Q_INVOKABLE void getContacts();
    // 添加用户（联系人）: POST /api/service/contacts
    Q_INVOKABLE void addContact(const QString &nickname, const QString &groupNickname, const QString &avatar);
    // 更新联系人信息（昵称/备注/群内昵称/头像）: PUT /api/service/contacts/:userId
    Q_INVOKABLE void updateContact(const QString &userId, const QString &nickname, const QString &groupNickname, const QString &avatar);

    // === 群组管理 ===
    // 获取本客服下的群列表（含成员）: GET /api/service/groups
    Q_INVOKABLE void getGroups();
    // 获取指定群的成员列表: GET /api/service/groups/:id/members
    Q_INVOKABLE void getGroupMembers(const QString &groupId);
    // 创建新群组: POST /api/service/groups
    Q_INVOKABLE void createGroup(const QString &name);
    // 更新群名称/头像（仅群主）: PUT /api/service/groups/:groupId
    Q_INVOKABLE void updateGroup(const QString &groupId, const QString &name, const QString &avatar);
    // 邀请用户入群: POST /api/service/groups/:groupId/members
    Q_INVOKABLE void inviteToGroup(const QString &groupId, const QString &userId);
    // 踢出群成员: DELETE /api/service/groups/:groupId/members/:userId
    Q_INVOKABLE void kickFromGroup(const QString &groupId, const QString &userId);
    // 解散群组（仅群主）: DELETE /api/service/groups/:groupId
    Q_INVOKABLE void dissolveGroup(const QString &groupId);
    // 获取客服自己的个人资料: GET /api/service/profile
    Q_INVOKABLE void getProfile();
    // 更新客服自己的个人资料: PUT /api/service/profile
    Q_INVOKABLE void updateProfile(const QString &nickname, const QString &avatar);

    // === 文件上传 ===
    // 上传通用文件（图片/文档等），上传成功后发出 uploadSuccess 信号
    Q_INVOKABLE void uploadFile(const QString &filePath);
    // 上传头像图片，上传成功后发出 avatarUploaded 信号
    Q_INVOKABLE void uploadAvatar(const QString &filePath);

    // === 文件下载 ===
    // 下载文件并使用系统默认应用打开
    Q_INVOKABLE void downloadAndOpen(const QString &url, const QString &fileName);
    // 下载文件到指定保存路径
    Q_INVOKABLE void downloadToPath(const QString &url, const QString &savePath);

    // === 剪贴板 ===
    // 复制文本到系统剪贴板
    Q_INVOKABLE void copyToClipboard(const QString &text);
    // 获取剪贴板内容类型和数据: {type: "image"/"file"/"text"/"none", text: "...", paths: [...]}
    Q_INVOKABLE QJsonObject getClipboardContent();
    // 将剪贴板中的图片保存到临时文件，返回文件路径（空表示失败）
    Q_INVOKABLE QString saveClipboardImage();
    // 下载远程文件后复制到系统剪贴板（可粘贴到资源管理器）
    Q_INVOKABLE void copyFileToClipboard(const QString &url, const QString &fileName);
    // 将链接保存为 txt 文件并复制文件到剪贴板
    Q_INVOKABLE void copyLinkAsFile(const QString &link);

    // 下载远程文件后启动系统拖放操作（拖到资源管理器可保存）
    Q_INVOKABLE void startFileDrag(const QString &url, const QString &fileName);

    // === 设置（持久化） ===
    // 保存登录配置到本地（userId + serverUrl），下次启动自动填充
    Q_INVOKABLE void saveLoginConfig(const QString &userId, const QString &serverUrl);
    // 读取上次保存的登录配置
    Q_INVOKABLE QJsonObject loadLoginConfig();

    // === 通用设置存取 ===
    Q_INVOKABLE void setSetting(const QString &key, const QString &value);
    Q_INVOKABLE QString getSetting(const QString &key, const QString &defaultValue = {});

signals:
    void baseUrlChanged();      // 服务器地址变更
    void tokenChanged();        // 认证令牌变更
    void serviceUserIdChanged(); // 客服用户ID变更

    // ── 登录相关信号 ──
    void loginSuccess(const QJsonObject &data);  // 登录成功，data 包含 token/userId/nickname
    void loginFailed(const QString &error);      // 登录失败

    // ── 联系人相关信号 ──
    void contactsLoaded(const QJsonArray &contacts); // 联系人列表加载完成
    void contactAdded(const QJsonObject &contact);   // 新增联系人成功
    void contactUpdated(const QJsonObject &contact); // 更新联系人成功
    void contactError(const QString &error);         // 联系人操作失败
    void profileUpdated(const QJsonObject &data);    // 个人资料更新成功

    // ── 群组相关信号 ──
    void groupsLoaded(const QJsonArray &groups);     // 群列表加载完成
    void groupMembersLoaded(const QString &groupId, const QVariantList &members); // 群成员列表加载完成
    void groupCreated();                             // 创建群组成功
    void groupUpdated(const QString &groupId);       // 更新群信息成功
    void groupMemberChanged(const QString &groupId); // 群成员变化（邀请/踢出后刷新）
    void groupError(const QString &error);           // 群操作失败

    // ── 上传相关信号 ──
    void uploadSuccess(const QString &url, const QString &fileName, qint64 fileSize); // 文件上传成功
    void uploadFailed(const QString &error);   // 文件上传失败
    void avatarUploaded(const QString &url);   // 头像上传成功，返回服务器URL

    // ── 下载相关信号 ──
    void downloadFinished(const QString &localPath); // 下载完成，localPath 为本地路径
    void downloadFailed(const QString &error);       // 下载失败

private:
    // 统一处理网络响应：解析 JSON、校验 code、回调 onSuccess/onError
    void handleReply(QNetworkReply *reply,
                     std::function<void(const QJsonObject &)> onSuccess,
                     std::function<void(const QString &)> onError);
    // 构造带 Token 和 ServiceUserID 的认证请求头
    QNetworkRequest authedRequest(const QString &path) const;
    // 执行系统拖放操作
    void performDrag(const QString &localPath);

    QNetworkAccessManager m_nam;   // Qt 网络访问管理器
    QString m_baseUrl;             // 服务器基础地址
    QString m_token;               // JWT 认证令牌
    QString m_serviceUserId;       // 当前客服用户ID
    QTemporaryDir m_tempDir;       // 临时下载目录（应用退出后自动清理）

    // 上传缓存: key = "path|size|lastModified" → 服务器URL（避免重复上传同一文件）
    QHash<QString, QString> m_uploadCache;
};

#endif // HTTPCLIENT_H
