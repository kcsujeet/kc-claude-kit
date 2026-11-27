export const RefundPanel = ({ order }: Props) => {
  const { refund, isLoading } = useRefund(order.id)
  return <RefundView refund={refund} isLoading={isLoading} />
}
