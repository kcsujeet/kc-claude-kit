import { act } from 'test-lib'
import useCartStore from '@/store/cart'

/** Turns on gift wrapping for the test store. */
const enableGiftWrap = () => {
  act(() => {
    useStoreContext.getState().setSelectedStore(mockStore)
    useCartStore.setState({
      options: { giftWrap: [mockStore.id] }
    })
  })
}

export default enableGiftWrap
