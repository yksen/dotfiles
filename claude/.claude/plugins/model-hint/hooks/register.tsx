import type { Register } from 'claude-code'

export const register: Register = on => {
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const model = await $.session.model()
    const effortLevel = (await $.settings.read()).effortLevel as string | undefined
    const tail = effortLevel ? `${model} · ${effortLevel}` : model

    return next({ ...e, props: { ...e.props, tail } })
  })
}
