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
