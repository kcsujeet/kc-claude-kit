import { useState } from 'react'
export const copy = (text: string) => navigator.clipboard.writeText(text)
