#include "messagecache.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>

MessageCache::MessageCache(QObject *parent)
    : QObject(parent)
{
}

MessageCache::~MessageCache()
{
    if (m_db.isOpen())
        m_db.close();
}

void MessageCache::init(const QString &userId)
{
    m_userId = userId;

    // 数据库文件存放在用户本地数据目录下，按用户ID隔离
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(dataDir);
    QString dbPath = dataDir + "/msg_cache_" + userId + ".db";

    // 使用唯一连接名，避免多实例冲突
    QString connName = "msg_cache_" + userId;
    if (QSqlDatabase::contains(connName)) {
        m_db = QSqlDatabase::database(connName);
    } else {
        m_db = QSqlDatabase::addDatabase("QSQLITE", connName);
        m_db.setDatabaseName(dbPath);
    }

    if (!m_db.open()) {
        qWarning() << "[MessageCache] 打开数据库失败:" << m_db.lastError().text();
        return;
    }

    // 开启 WAL 模式提高并发读写性能
    QSqlQuery pragma(m_db);
    pragma.exec("PRAGMA journal_mode=WAL");
    pragma.exec("PRAGMA synchronous=NORMAL");

    createTable();
    qDebug() << "[MessageCache] 数据库已初始化:" << dbPath;
}

void MessageCache::createTable()
{
    QSqlQuery q(m_db);
    q.exec(R"(
        CREATE TABLE IF NOT EXISTS messages (
            clientMsgID   TEXT PRIMARY KEY,
            serverMsgID   TEXT,
            peerUserId    TEXT NOT NULL,
            sendID        TEXT,
            recvID        TEXT,
            contentType   INTEGER DEFAULT 101,
            sendTime      INTEGER DEFAULT 0,
            status        INTEGER DEFAULT 2,
            rawJson       TEXT
        )
    )");
    if (q.lastError().isValid())
        qWarning() << "[MessageCache] 建表失败:" << q.lastError().text();

    // 按会话+时间索引，加速按会话加载
    q.exec("CREATE INDEX IF NOT EXISTS idx_peer_time ON messages(peerUserId, sendTime)");
    // 按 serverMsgID 索引，加速删除
    q.exec("CREATE INDEX IF NOT EXISTS idx_server_id ON messages(serverMsgID)");
}

void MessageCache::saveMessage(const QJsonObject &msg)
{
    if (!m_db.isOpen()) return;

    QString clientMsgID = msg["clientMsgID"].toString();
    if (clientMsgID.isEmpty()) return;

    QString serverMsgID = msg["serverMsgID"].toString();
    QString sendID = msg["sendID"].toString();
    QString recvID = msg["recvID"].toString();
    int contentType = msg["contentType"].toInt(101);
    qint64 sendTime = static_cast<qint64>(msg["sendTime"].toDouble());
    int status = msg["status"].toInt(2);

    // 计算 peerUserId：对方的 ID
    QString peerUserId = (sendID == m_userId) ? recvID : sendID;

    // 将完整消息 JSON 序列化存储，加载时直接还原
    QString rawJson = QString::fromUtf8(QJsonDocument(msg).toJson(QJsonDocument::Compact));

    QSqlQuery q(m_db);
    q.prepare(R"(
        INSERT INTO messages (clientMsgID, serverMsgID, peerUserId, sendID, recvID, contentType, sendTime, status, rawJson)
        VALUES (:cid, :sid, :peer, :send, :recv, :ct, :st, :status, :raw)
        ON CONFLICT(clientMsgID) DO UPDATE SET
            serverMsgID = COALESCE(NULLIF(:sid2, ''), serverMsgID),
            status = :status2,
            sendTime = CASE WHEN :st2 > 0 THEN :st2 ELSE sendTime END,
            rawJson = :raw2
    )");
    q.bindValue(":cid", clientMsgID);
    q.bindValue(":sid", serverMsgID);
    q.bindValue(":peer", peerUserId);
    q.bindValue(":send", sendID);
    q.bindValue(":recv", recvID);
    q.bindValue(":ct", contentType);
    q.bindValue(":st", sendTime);
    q.bindValue(":status", status);
    q.bindValue(":raw", rawJson);
    q.bindValue(":sid2", serverMsgID);
    q.bindValue(":status2", status);
    q.bindValue(":st2", sendTime);
    q.bindValue(":raw2", rawJson);

    if (!q.exec())
        qWarning() << "[MessageCache] saveMessage 失败:" << q.lastError().text();
}

void MessageCache::saveMessages(const QJsonArray &msgs)
{
    if (!m_db.isOpen() || msgs.isEmpty()) return;

    m_db.transaction();
    for (const auto &val : msgs) {
        saveMessage(val.toObject());
    }
    m_db.commit();
}

QJsonArray MessageCache::loadMessages(const QString &peerUserId, int limit)
{
    QJsonArray result;
    if (!m_db.isOpen()) return result;

    QSqlQuery q(m_db);
    q.prepare(R"(
        SELECT rawJson FROM messages
        WHERE peerUserId = :peer
        ORDER BY sendTime DESC
        LIMIT :limit
    )");
    q.bindValue(":peer", peerUserId);
    q.bindValue(":limit", limit);

    if (!q.exec()) {
        qWarning() << "[MessageCache] loadMessages 失败:" << q.lastError().text();
        return result;
    }

    // 结果是倒序的，需要反转为时间升序
    QJsonArray reversed;
    while (q.next()) {
        QJsonDocument doc = QJsonDocument::fromJson(q.value(0).toString().toUtf8());
        reversed.append(doc.object());
    }
    for (int i = reversed.size() - 1; i >= 0; --i)
        result.append(reversed[i]);

    return result;
}

QJsonArray MessageCache::loadMessagesBefore(const QString &peerUserId, qint64 beforeTime, int limit)
{
    QJsonArray result;
    if (!m_db.isOpen()) return result;

    QSqlQuery q(m_db);
    q.prepare(R"(
        SELECT rawJson FROM messages
        WHERE peerUserId = :peer AND sendTime < :before
        ORDER BY sendTime DESC
        LIMIT :limit
    )");
    q.bindValue(":peer", peerUserId);
    q.bindValue(":before", beforeTime);
    q.bindValue(":limit", limit);

    if (!q.exec()) {
        qWarning() << "[MessageCache] loadMessagesBefore 失败:" << q.lastError().text();
        return result;
    }

    QJsonArray reversed;
    while (q.next()) {
        QJsonDocument doc = QJsonDocument::fromJson(q.value(0).toString().toUtf8());
        reversed.append(doc.object());
    }
    for (int i = reversed.size() - 1; i >= 0; --i)
        result.append(reversed[i]);

    return result;
}

qint64 MessageCache::getLatestSendTime(const QString &peerUserId)
{
    if (!m_db.isOpen()) return 0;

    QSqlQuery q(m_db);
    q.prepare("SELECT MAX(sendTime) FROM messages WHERE peerUserId = :peer");
    q.bindValue(":peer", peerUserId);

    if (q.exec() && q.next())
        return q.value(0).toLongLong();
    return 0;
}

void MessageCache::updateMessageStatus(const QString &clientMsgID, int status, const QString &serverMsgID, qint64 sendTime)
{
    if (!m_db.isOpen() || clientMsgID.isEmpty()) return;

    // 1) 读取现有 rawJson
    QSqlQuery sel(m_db);
    sel.prepare("SELECT rawJson FROM messages WHERE clientMsgID = :cid");
    sel.bindValue(":cid", clientMsgID);
    if (!sel.exec() || !sel.next()) return;

    // 2) 在原始 JSON 上仅修改状态字段，保留所有内容字段
    QJsonDocument doc = QJsonDocument::fromJson(sel.value(0).toString().toUtf8());
    QJsonObject obj = doc.object();
    obj["status"] = status;
    if (!serverMsgID.isEmpty())
        obj["serverMsgID"] = serverMsgID;
    if (sendTime > 0)
        obj["sendTime"] = static_cast<double>(sendTime);

    QString newRaw = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

    // 3) 写回
    QSqlQuery upd(m_db);
    upd.prepare(R"(
        UPDATE messages SET
            serverMsgID = COALESCE(NULLIF(:sid, ''), serverMsgID),
            status      = :status,
            sendTime    = CASE WHEN :st > 0 THEN :st ELSE sendTime END,
            rawJson     = :raw
        WHERE clientMsgID = :cid
    )");
    upd.bindValue(":sid", serverMsgID);
    upd.bindValue(":status", status);
    upd.bindValue(":st", sendTime);
    upd.bindValue(":raw", newRaw);
    upd.bindValue(":cid", clientMsgID);

    if (!upd.exec())
        qWarning() << "[MessageCache] updateMessageStatus 失败:" << upd.lastError().text();
}

void MessageCache::removeMessage(const QString &serverMsgID)
{
    if (!m_db.isOpen() || serverMsgID.isEmpty()) return;

    QSqlQuery q(m_db);
    q.prepare("DELETE FROM messages WHERE serverMsgID = :sid");
    q.bindValue(":sid", serverMsgID);
    q.exec();
}

void MessageCache::clearChat(const QString &peerUserId)
{
    if (!m_db.isOpen()) return;

    QSqlQuery q(m_db);
    q.prepare("DELETE FROM messages WHERE peerUserId = :peer");
    q.bindValue(":peer", peerUserId);
    q.exec();
}
