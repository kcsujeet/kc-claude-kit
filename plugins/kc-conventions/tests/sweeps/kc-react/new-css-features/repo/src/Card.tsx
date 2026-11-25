const style = {
  containerType: 'size',
  pt: '20cqw',
}
const full = { minHeight: '100dvh' }
const row = { containerType: 'inline-size', '& .mark': { pt: '20cqw' } }
const stack = { '& .a': { pt: '5cqh' }, containerType: 'size' }
const sheet = `@supports (aspect-ratio: 1) { .x { width: 10svh } }`
const plain = { paddingTop: '20%' }
