import jQuery from 'jquery'
import riot from 'riot'

import 'riot-hot-reload'

import './edit.tag.pug'
import './postgresql.tag.pug'
import './help-edit.tag.pug'
import './help-general.tag.pug'
import './postgresqls.tag.pug'
import './logs.tag.pug'
import './new.tag.pug'
import './status.tag.pug'
import './app.tag.pug'
import './restore.tag.pug'

Object.fromEntries = entries => entries.length === 0 ? {} : Object.assign(...entries.map(([k, v]) => ({[k]: v})))
Object.mapValues = (o, f) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, f(v, k)]))
Object.mapEntries = (o, f) => Object.fromEntries(Object.entries(o).map(f).filter(x => x))
Object.filterEntries = (o, f) => Object.mapEntries(o, entry => f(entry) && entry)
Object.filterValues = (o, f) => Object.filterEntries(o, ([key, value]) => f(value) && [key, value])


const getDefaulting = (object, key, def) => (
    object.hasOwnProperty(key) ? object[key] : def
)


const Dynamic = (options={}) => {
    const instance = {
        init: getDefaulting(options, 'init', () => ''),
        refresh: getDefaulting(options, 'refresh', () => true),
        update: getDefaulting(options, 'update', value => (instance.state = value, true)),
        validState: getDefaulting(options, 'validState', state => (
            state !== undefined &&
      state !== null &&
      typeof state === 'string' &&
      state.length > 0
        )),

        edit: event => (instance.update(event.target.value, instance, event), true),
        valid: () => instance.validState(instance.state),
    }

    instance.state = instance.init()
    return instance
}


/*
Dynamics manages a dynamic array whose elements are themselves Dynamic objects.

The default initializer builds an empty array as the initial state.

The "add" DOM event callback is provided to add a newly initialized Dynamic
object to the end of the state array.  The Dynamic array item is initialized
with the "itemInit" callback, which can be specified with a constructor option
and defaults to creating a Dynamic with all default options.

The "remove" DOM event callback is provided to handle DOM events that should
or remove a specific item.  For events on elements generated by iterating the
state with an each= attribute, the event.item will be set to the correct value.

The refresh callback is forwarded to all constituent Dynamic objects.
*/
const Dynamics = (options={}) => {
    const instance = Object.assign(
        Dynamic(
            Object.assign(
                { init: () => [] },
                'refresh' in options
                    ? { refresh: options.refresh }
                    : undefined
            )
        ),

        {
            itemInit: getDefaulting(options, 'itemInit', () =>
                Dynamic(
                    'refresh' in options
                        ? { refresh: options.refresh }
                        : {}
                )
            ),
            itemValid: getDefaulting(options, 'itemValid', item => item.valid()),
            validState: state => state.every(instance.itemValid),
            update: () => true,
            edit: () => true,

            add: _event => {
                instance.state.push(instance.itemInit())
                instance.refresh()
                return true
            },

            remove: event => {
                instance.state.splice(instance.state.indexOf(event.item), 1)
                instance.refresh()
                return true
            },
        }
    )

    Object.defineProperty(instance, 'valids', { get: () =>
        instance.state.filter(instance.itemValid)
    })

    return instance
}


/*
DynamicSet manages a keyed collection of Dynamic objects.  The constructor
receives an object mapping keys to initialization functions, and its state is a
mapping from the same keys to Dynamics initialized using the corresponding
key's initialization function.  A DynamicSet is valid when its constituent
Dynamics are all simultaneously valid.  The refresh callback is forwarded to
all constituent Dynamic objects.

Example:

  DynamicSet({
    foo: undefined,
    bar: () => 'baz',
  })

This call would create a DynamicSet with two constituent dynamics in its state:
one of them under the 'foo' key of the state object, built with the default
Dynamic initializer, and another under the 'bar' key of the state object, whose
state, in turn, would initially hold the value 'baz'.
*/
const DynamicSet = (items, options={}) => Object.assign(
    Dynamic(
        Object.assign(
            {
                init: () => Object.mapValues(items, init =>
                    Dynamic(
                        Object.assign(
                            init ? { init: init } : undefined,
                            'refresh' in options ? { refresh: options.refresh } : undefined
                        )
                    )
                ),
            },
            'refresh' in options
                ? { refresh: options.refresh }
                : undefined
        )
    ),

    {
        items: items,
        validState: state => Object.values(state).every(item => item.valid()),
        edit: () => true,
        update: () => true,
    }
)


const delete_cluster = (namespace, clustername) => {
    jQuery.confirm({
        backgroundDismiss: true,
        content: `
      <p>
        Are you sure you want to remove this PostgreSQL cluster?  If so,
        please <strong>type the cluster name here
        (<code>${namespace}/${clustername}</code>)</strong> and click the
        confirm button:
      </p>
      <input
        type="text"
        class="confirm-delete"
        placeholder="cluster name"
        style="width: 100%"
      >
      <hr>
      <p><small>
        <strong>Note</strong>: if you create a cluster with the same name as
        this one after deleting it, the new cluster will restore the data
        from this cluster's current backups stored in AWS S3.  This behavior
        will change soon and you will be able to reuse a cluster name and
        get a completely new cluster.
      </small></p>
    `,
        escapeKey: true,
        icon: 'glyphicon glyphicon-warning-sign',
        title: 'Confirm cluster deletion?',
        typeAnimated: true,
        type: 'red',
        onOpen: function () {
            const dialog = this
            const confirm = dialog.buttons.confirm
            const confirmSelector = jQuery(confirm.el)
            const input = dialog.$content.find('input')
            input.on('input', () => {
                if (input.val() === namespace + '/' + clustername) {
                    confirmSelector.removeClass('btn-default').addClass('btn-danger')
                    confirm.enable()
                } else {
                    confirm.disable()
                    confirmSelector.removeClass('btn-danger').addClass('btn-default')
                }
            })
        },
        buttons: {
            cancel: {
                text: 'Cancel',
            },
            confirm: {
                btnClass: 'btn-default',
                isDisabled: true,
                text: 'Delete cluster',
                action: () => {
                    jQuery.ajax({
                        type: 'DELETE',
                        url: (
                            '/postgresqls/'
              + encodeURI(namespace)
              + '/' + encodeURI(clustername)
                        ),
                        dataType: 'text',
                        success: () => location.assign('/#/list'),
                        error: (r, status, error) => location.assign('/#/list'), // TODO: show error
                    })
                },
            },
        }
    })
}


/* Unfortunately, there does not appear to be a good way to import local modules
inside a Riot tag, so we define/import things here and pass them manually in the
opts variable.  Remember to propagate opts manually when instantiating tags.  */
riot.mount('app', {
    Dynamic: Dynamic,
    Dynamics: Dynamics,
    DynamicSet: DynamicSet,
    delete_cluster: delete_cluster,
})
