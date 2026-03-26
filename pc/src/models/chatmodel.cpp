#include "chatmodel.h"

#include <QUuid>
#include <QJsonDocument>
#include <QJsonArray>
#include <QSet>

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
    }
    return {};
}

QHash<int, QByteArray> ChatModel::roleNames() const
{
    return {
        { ClientMsgIDRole, "clientMsgID" },
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
    };
}

void ChatModel::appendMessage(const QJsonObject &msg)
{
    ChatMessage m = fromJson(msg);
    beginInsertRows(QModelIndex(), m_messages.size(), m_messages.size());
    m_messages.append(m);
    endInsertRows();
    emit countChanged();
}

void ChatModel::prependMessages(const QJsonArray &msgs)
{
    if (msgs.isEmpty()) return;
    // Build list, filtering duplicates
    QVector<ChatMessage> newMsgs;
    QSet<QString> existing;
    for (const auto &m : m_messages)
        existing.insert(m.clientMsgID);
    for (const auto &val : msgs) {
        ChatMessage cm = fromJson(val.toObject());
        if (!existing.contains(cm.clientMsgID))
            newMsgs.append(cm);
    }
    if (newMsgs.isEmpty()) return;
    beginInsertRows(QModelIndex(), 0, newMsgs.size() - 1);
    for (int i = newMsgs.size() - 1; i >= 0; --i)
        m_messages.prepend(newMsgs[i]);
    endInsertRows();
    emit countChanged();
}

QString ChatModel::addPendingMessage(const QString &recvId, int contentType,
                                      const QString &text, const QString &imageUrl,
                                      const QString &fileName, qint64 fileSize)
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
    msg.sendTime = QDateTime::currentMSecsSinceEpoch();
    msg.status = 1; // 发送中

    beginInsertRows(QModelIndex(), m_messages.size(), m_messages.size());
    m_messages.append(msg);
    endInsertRows();
    emit countChanged();
    return msg.clientMsgID;
}

void ChatModel::updateStatus(const QString &clientMsgID, int status)
{
    for (int i = 0; i < m_messages.size(); ++i) {
        if (m_messages[i].clientMsgID == clientMsgID) {
            m_messages[i].status = status;
            QModelIndex idx = index(i);
            emit dataChanged(idx, idx, { StatusRole });
            return;
        }
    }
}

void ChatModel::clear()
{
    beginResetModel();
    m_messages.clear();
    endResetModel();
    emit countChanged();
}

ChatMessage ChatModel::fromJson(const QJsonObject &obj) const
{
    ChatMessage m;
    m.clientMsgID = obj["clientMsgID"].toString();
    m.sendID = obj["sendID"].toString();
    m.recvID = obj["recvID"].toString();
    m.contentType = obj["contentType"].toInt(101);
    m.sendTime = static_cast<qint64>(obj["sendTime"].toDouble());
    m.status = obj["status"].toInt(2);

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
        // 图片消息 —— 同时支持 OpenIM 格式和简化 {url} 格式
        QJsonObject pic = obj["pictureElem"].toObject();
        QJsonObject src = pic["sourcePicture"].toObject();
        m.imageUrl = src["url"].toString();
        if (m.imageUrl.isEmpty())
            m.imageUrl = pic["bigPicture"].toObject()["url"].toString();
        if (m.imageUrl.isEmpty())
            m.imageUrl = pic["url"].toString();
    } else if (m.contentType == 105) {
        // 文件消息 —— 同时支持 OpenIM 格式和简化 {url,name,size} 格式
        QJsonObject fileElem = obj["fileElem"].toObject();
        m.fileName = fileElem["fileName"].toString();
        if (m.fileName.isEmpty())
            m.fileName = fileElem["name"].toString();
        m.fileSize = static_cast<qint64>(fileElem["fileSize"].toDouble());
        if (m.fileSize == 0)
            m.fileSize = static_cast<qint64>(fileElem["size"].toDouble());
        m.imageUrl = fileElem["sourceUrl"].toString();
        if (m.imageUrl.isEmpty())
            m.imageUrl = fileElem["url"].toString();
    } else if (m.contentType == 103) {
        // 语音消息 —— 支持 {url, duration} 格式
        QJsonObject voiceElem = obj["voiceElem"].toObject();
        m.imageUrl = voiceElem["sourceUrl"].toString();
        if (m.imageUrl.isEmpty())
            m.imageUrl = voiceElem["url"].toString();
        m.voiceDuration = voiceElem["duration"].toInt();
    }

    return m;
}
