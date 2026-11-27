export const OrderPanel = ({ order }: Props) => {
  const { receipt: fetchedReceipt, isLoading } = useOrderReceipt(order.id)
  const receipt = order.isManual ? manualReceipt(order) : fetchedReceipt
  return <ReceiptView receipt={receipt} isLoading={isLoading} />
}

export const OrderTotals = ({ order }: Props) => {
  const { totals } = useOrderTotals(order.id)
  if (totals.isEmpty) return null
  return <TotalsTable rows={totals.rows} />
}

export const OrderTitle = ({ order }: Props) => {
  const t = useTranslations()
  return <h2>{t('orders.title')}</h2>
}

export const OrderNotes = ({ order }: Props) => {
  const notes = useOrderNotes(order.id)
  return <NotesList notes={notes} />
}

export const OrderBox = ({ order }: Props) => {
  const { label } = useOrderLabel(order.id)
  const body = <LabelView label={label} />
  return <Card>{body}</Card>
}
