import dayjs from 'dayjs'
import { useState } from 'react'
import { copy } from './useClipboard'
const pad = { pt: '20cqw', height: '100dvh' }
const share = (data: object) => navigator.share(data)
const paste = (text: string) => navigator.clipboard.writeText(text)
