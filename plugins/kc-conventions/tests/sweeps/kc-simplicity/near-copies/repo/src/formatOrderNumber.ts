export const formatOrderNumber = (order: Order) => {
  return order.prefix + String(order.sequence).padStart(6, '0')
}
