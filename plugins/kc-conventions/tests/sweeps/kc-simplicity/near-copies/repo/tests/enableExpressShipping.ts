import { act } from 'test-lib'
import useCartStore from '@/store/cart'

/** Turns on express shipping for the test store. */
export const enableExpressShipping = () => {
  act(() => {
    useStoreContext.getState().setSelectedStore(mockStore)
    useCartStore.setState({
      options: { expressShipping: [mockStore.id] }
    })
  })
}
