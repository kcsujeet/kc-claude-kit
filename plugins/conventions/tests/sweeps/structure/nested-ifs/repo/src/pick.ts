export const pick = (a: boolean, b: boolean) => {
  if (a) {
    if (b) {
      return 1
    }
  }
  if (a) {
    return 2
  } else if (b) {
    return 3
  } else {
    if (a && b) return 4
  }
  return 0
}
