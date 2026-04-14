export interface Message {
  clientMsgID: string
  serverMsgID?: string
  sendID: string
  recvID: string
  sessionType: number
  contentType: number // 101=text, 102=picture, 103=voice, 105=file
  content: string
  sendTime: number
  status: number // 1=sending, 2=sent, 3=failed
  isRead?: boolean
  isGroup?: boolean      // 是否群消息
  senderName?: string    // 发送者在群内的显示名（群消息时携带）
  senderAvatar?: string  // 发送者头像 URL（群消息时携带）
  groupId?: string       // 群消息时的群 ID
  groupName?: string     // 群消息时的群名称
  // Parsed content based on contentType
  textContent?: string
  pictureContent?: PictureContent
  voiceContent?: VoiceContent
  fileContent?: FileContent
}

export interface PictureContent {
  sourcePath?: string
  sourcePicture?: PictureInfo
  bigPicture?: PictureInfo
  snapshotPicture?: PictureInfo
}

export interface PictureInfo {
  uuid?: string
  type?: string
  size?: number
  width?: number
  height?: number
  url?: string
}

export interface VoiceContent {
  uuid?: string
  soundPath?: string
  sourceUrl?: string
  dataSize?: number
  duration?: number
}

export interface FileContent {
  filePath?: string
  uuid?: string
  sourceUrl?: string
  fileName?: string
  fileSize?: number
  fileType?: string
}

export interface UserInfo {
  userId: string
  token: string
  serviceUserId: string
  wsUrl: string
  apiUrl: string
}
