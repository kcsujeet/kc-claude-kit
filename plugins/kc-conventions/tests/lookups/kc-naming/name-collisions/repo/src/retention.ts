export const check = (policy: Policy) => policy.days > 0
export const checkRetention = () => check(defaultPolicy)
