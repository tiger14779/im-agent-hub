#include "chatmodel.h"

#include <QUuid>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFile>
#include <QUrl>
#include <algorithm>

ChatModel::ChatModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ChatModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_messages.size();
}

QVariant ChatModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_messages.size())
        return {};

    const ChatMessage &msg = m_messages.at(index.row());

    switch (role) {
    case ClientMsgIDRole: return msg.clientMsgID;
    case ServerMsgIDRole: return msg.serverMsgID;
    case SendIDRole:      return msg.sendID;
    case RecvIDRole:      return msg.recvID;
    case ContentTypeRole: return msg.contentType;
    case TextContentRole: return msg.textContent;
    case ImageUrlRole:    return msg.imageUrl;
    case FileNameRole:    return msg.fileName;
    case FileSizeRole:    return msg.fileSize;
    case VoiceDurationRole: return msg.voiceDuration;
    case SendTimeRole:    return msg.sendTime;
    case StatusRole:      return msg.status;
    case IsSelfRole:      return msg.sendID == m_selfId;
    case SenderNameRole:   return msg.senderName;
    case SenderAvatarRole: return msg.senderAvatar;
    case IsGroupRole:      return msg.isGroup;
    default:               return {};
    }
}

QHash<int, QByteArray> ChatModel::roleNames() const
{
    return {
        { ClientMsgIDRole, "clientMsgID" },
        { ServerMsgIDRole, "serverMsgID" },
        { SendIDRole,      "sendID" },
        { RecvIDRole,      "recvID" },
        { ContentTypeRole, "contentType" },
        { TextContentRole, "textContent" },
        { ImageUrlRole,    "imageUrl" },
        { FileNameRole,    "fileName" },
        { FileSizeRole,    "fileSize" },
        { VoiceDurationRole, "voiceDuration" },
        { SendTimeRole,    "sendTime" },
        { StatusRole,      "status" },
        { IsSelfRole,      "isSelf" },
        { SenderNameRole,   "senderName" },
        { SenderAvatarRole, "senderAvatar" },
        { IsGroupRole,      "isGroup" },
    };
}

void ChatModel::appendMessage(const QJsonObject &msg)
{
    ChatMessage m = fromJson(msg);
    // Dedup: if clientMsgID already exists, update in place (server data refreshes stale cache)
    if (!m.clientMsgID.isEmpty() && m_idSet.contains(m.clientMsgID)) {
        for (int i = 0; i < m_messages.size(); ++i) {
            if (m_messages[i].clientMsgID == m.clientMsgID) {
                m_messages[i] = m;
                QModelIndex idx = index(i);
                emit dataChanged(idx, idx);
                return;
            }
        }
    }

    // 按 sendTime 升序插入：若消息时间早于当前最新消息，搜索正确位置插入而不是盲目追加
    // （防止重连同步或离线消息延迟到达时旧消息出现在底部）
    int insertPos = m_messages.size(); // default: append to end
    if (m.sendTime > 0 && !m_messages.isEmpty() && m.sendTime < m_messages.last().sendTime) {
        // Binary search for sorted insertion point
        int lo = 0, hi = m_messages.size() - 1;
        while (lo <= hi) {
            int mid = (lo + hi) / 2;
            if (m_messages[mid].sendTime <= m.sendTime)
                lo = mid + 1;
            else
                hi = mid - 1;
        }
        insertPos = lo;
    }

    beginInsertRows(QModelIndex(), insertPos, insertPos);
    if (!m.clientMsgID.isEmpty())
        m_idSet.insert(m.clientMsgID);
    m_messages.insert(insertPos, m);
    endInsertRows();
    emit countChanged();
}

void ChatModel::prependMessages(const QJsonArray &msgs)
{
    if (msgs.isEmpty()) return;
    // Build list, filtering duplicates using class-level m_idSet (O(1) per lookup)
    QVector<ChatMessage> newMsgs;
    for (const auto &val : msgs) {
        ChatMessage cm = fromJson(val.toObject());
        if (!m_idSet.contains(cm.clientMsgID))
            newMsgs.append(cm);
    }
    if (newMsgs.isEmpty()) return;
    // 按 sendTime 升序排序，确保历史消息顺序正确
    std::sort(newMsgs.begin(), newMsgs.end(), [](const ChatMessage &a, const ChatMessage &b) {
        return a.sendTime < b.sendTime;
    });
    beginInsertRows(QModelIndex(), 0, newMsgs.size() - 1);
    for (int i = newMsgs.size() - 1; i >= 0; --i) {
        m_idSet.insert(newMsgs[i].clientMsgID);
        m_messages.prepend(newMsgs[i]);
    }
    endInsertRows();
    emit countChanged();
}

QString ChatModel::addPendingMessage(const QString &recvId, int contentType,
                                      const QString &text, const QString &imageUrl,
                                      const QString &fileName, qint64 fileSize, int voiceDuration)
{
    ChatMessage msg;
    msg.clientMsgID = QUuid::createUuid().toString(QUuid::WithoutBraces);
    msg.sendID = m_selfId;
    msg.recvID = recvId;
    msg.contentType = contentType;
    msg.textContent = text;
    msg.imageUrl = imageUrl;
    msg.fileName = fileName;
    msg.fileSize = fileSize;
    msg.voiceDuration = voiceDuration;
    msg.sendTime = QDateTime::currentMSecsSinceEpoch();
    msg.status = 1; // 发送中

    beginInsertRows(QModelIndex(), m_messages.size(), m_messages.size());
    m_idSet.insert(msg.clientMsgID);
    m_messages.append(msg);
    endInsertRows();
    emit countChanged();
    return msg.clientMsgID;
}

QString ChatModel::generateMsgId()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

bool ChatModel::hasMessage(const QString &clientMsgID) const
{
    if (clientMsgID.isEmpty())
        return false;
    return m_idSet.contains(clientMsgID);
}

void ChatModel::updateStatus(const QString &clientMsgID, int status, const QString &serverMsgID)
{
    for (int i = 0; i < m_messages.size(); ++i) {
        if (m_messages[i].clientMsgID == clientMsgID) {
            m_messages[i].status = status;
            if (!serverMsgID.isEmpty())
                m_messages[i].serverMsgID = serverMsgID;
            QModelIndex idx = index(i);
            emit dataChanged(idx, idx, { StatusRole, ServerMsgIDRole });
            return;
        }
    }
}

void ChatModel::clear()
{
    beginResetModel();
    m_messages.clear();
    m_idSet.clear();
    endResetModel();
    emit countChanged();
}

void ChatModel::replaceAll(const QJsonArray &msgs)
{
    QVector<ChatMessage> newList;
    newList.reserve(msgs.size());
    for (const auto &val : msgs)
        newList.append(fromJson(val.toObject()));
    // 按 sendTime 升序排序，确保消息顺序正确
    std::sort(newList.begin(), newList.end(), [](const ChatMessage &a, const ChatMessage &b) {
        return a.sendTime < b.sendTime;
    });

    const int oldSize = m_messages.size();
    const int newSize = newList.size();

    // Fast path: existing messages are a prefix of (or equal to) new messages
    // Common case: cache and server return same data, or server has a few extras
    if (oldSize > 0 && newSize >= oldSize) {
        bool prefixMatch = true;
        for (int i = 0; i < oldSize; ++i) {
            if (newList[i].clientMsgID != m_messages[i].clientMsgID) {
                prefixMatch = false;
                break;
            }
        }
        if (prefixMatch) {
            // Update existing data in place (status/serverMsgID may differ) — no layout change
            for (int i = 0; i < oldSize; ++i)
                m_messages[i] = newList[i];
            emit dataChanged(index(0), index(oldSize - 1));

            // Append any extra messages from server (new msgs arrived during round-trip)
            if (newSize > oldSize) {
                beginInsertRows(QModelIndex(), oldSize, newSize - 1);
                for (int i = oldSize; i < newSize; ++i) {
                    m_idSet.insert(newList[i].clientMsgID);
                    m_messages.append(newList[i]);
                }
                endInsertRows();
                emit countChanged();
            }
            return;
        }
    }

    // Empty model: just insert all
    if (oldSize == 0 && newSize > 0) {
        beginInsertRows(QModelIndex(), 0, newSize - 1);
        m_messages = std::move(newList);
        for (const auto &m : m_messages)
            m_idSet.insert(m.clientMsgID);
        endInsertRows();
        emit countChanged();
        return;
    }

    // Slow path: structure differs → clear then insert (same visual as original clear+prependMessages)
    beginResetModel();
    m_messages.clear();
    m_idSet.clear();
    endResetModel();
    emit countChanged();

    if (newSize > 0) {
        beginInsertRows(QModelIndex(), 0, newSize - 1);
        m_messages = std::move(newList);
        for (const auto &m : m_messages)
            m_idSet.insert(m.clientMsgID);
        endInsertRows();
        emit countChanged();
    }
}

ChatMessage ChatModel::fromJson(const QJsonObject &obj) const
{
    ChatMessage m;
    m.clientMsgID = obj["clientMsgID"].toString();
    m.serverMsgID = obj["serverMsgID"].toString();
    m.sendID = obj["sendID"].toString();
    m.recvID = obj["recvID"].toString();
    m.contentType = obj["contentType"].toInt(101);
    m.sendTime = static_cast<qint64>(obj["sendTime"].toDouble());
    m.status = obj["status"].toInt(2);

    // 检查本地已缓存的媒体文件（优先用本地路径，避免重复下载 + 图片闪烁）
    QString localPath = obj["localPath"].toString();
    bool useLocal = !localPath.isEmpty() && QFile::exists(localPath);

    // 根据消息类型解析对应的内容字段
    if (m.contentType == 101) {
        // 文本消息：优先从 textElem.text 取，其次 textElem.content，最后 fallback 到 content
        QJsonObject textElem = obj["textElem"].toObject();
        m.textContent = textElem["text"].toString();
        if (m.textContent.isEmpty())
            m.textContent = textElem["content"].toString();
        if (m.textContent.isEmpty())
            m.textContent = obj["content"].toString();
    } else if (m.contentType == 102) {
        // 图片消息 —— 有本地缓存则直接用 file:// 路径，否则从服务器 URL
        if (useLocal) {
            m.imageUrl = QUrl::fromLocalFile(localPath).toString();
        } else {
            QJsonObject pic = obj["pictureElem"].toObject();
            QJsonObject src = pic["sourcePicture"].toObject();
            m.imageUrl = src["url"].toString();
            if (m.imageUrl.isEmpty())
                m.imageUrl = pic["bigPicture"].toObject()["url"].toString();
            if (m.imageUrl.isEmpty())
                m.imageUrl = pic["url"].toString();
        }
    } else if (m.contentType == 105) {
        // 文件消息 —— 同上
        QJsonObject fileElem = obj["fileElem"].toObject();
        m.fileName = fileElem["fileName"].toString();
        if (m.fileName.isEmpty())
            m.fileName = fileElem["name"].toString();
        m.fileSize = static_cast<qint64>(fileElem["fileSize"].toDouble());
        if (m.fileSize == 0)
            m.fileSize = static_cast<qint64>(fileElem["size"].toDouble());
        if (useLocal) {
            m.imageUrl = QUrl::fromLocalFile(localPath).toString();
        } else {
            m.imageUrl = fileElem["sourceUrl"].toString();
            if (m.imageUrl.isEmpty())
                m.imageUrl = fileElem["url"].toString();
        }
    } else if (m.contentType == 103) {
        // 语音消息 —— 同上
        QJsonObject voiceElem = obj["voiceElem"].toObject();
        if (useLocal) {
            m.imageUrl = QUrl::fromLocalFile(localPath).toString();
        } else {
            m.imageUrl = voiceElem["sourceUrl"].toString();
            if (m.imageUrl.isEmpty())
                m.imageUrl = voiceElem["url"].toString();
        }
        m.voiceDuration = voiceElem["duration"].toInt();
    }

    // 群消息发送者名称/头像和群消息标记
    m.senderName   = obj["senderName"].toString();
    m.senderAvatar = obj["senderAvatar"].toString();
    m.isGroup      = obj["isGroup"].toBool(false);

    return m;
}

void ChatModel::removeMessageByServerMsgID(const QString &serverMsgID)
{
    if (serverMsgID.isEmpty()) return;
    for (int i = 0; i < m_messages.size(); ++i) {
        if (m_messages[i].serverMsgID == serverMsgID) {
            m_idSet.remove(m_messages[i].clientMsgID);
            beginRemoveRows(QModelIndex(), i, i);
            m_messages.removeAt(i);
            endRemoveRows();
            emit countChanged();
            return;
        }
    }
}

void ChatModel::updateImageUrl(const QString &clientMsgID, const QString &newUrl)
{
    if (clientMsgID.isEmpty()) return;
    for (int i = 0; i < m_messages.size(); ++i) {
        if (m_messages[i].clientMsgID == clientMsgID) {
            m_messages[i].imageUrl = newUrl;
            QModelIndex idx = index(i);
            emit dataChanged(idx, idx, { ImageUrlRole });
            return;
        }
    }
}
