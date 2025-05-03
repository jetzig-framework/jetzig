window.Jetzig = window.Jetzig ? window.Jetzig : {}
const Jetzig = window.Jetzig;

(() => {
  const state_tag = "__jetzig_channel_state__:";
  const actions_tag = "__jetzig_actions__:";
  const event_tag = "__jetzig_event__:";

  const transform = (value, state, element) => {
    const id = element.getAttribute('jetzig-id');
    const transformer = id && Jetzig.channel.transformers[id];
    if (transformer) {
        return transformer(value, state, element);
    } else {
        return value === undefined || value == null ? '' : `${value}`
    }
  };

  const reduceState = (ref, state) => {
    if (!ref.startsWith('$.')) throw new Error(`Unexpected ref format: ${ref}`);
    const args = ref.split('.');
    args.shift();
    const isNumeric = (string) => [...string].every(char => '0123456789'.includes(char));
    const isObject = (object) => object && typeof object === 'object';
    return args.reduce((acc, arg) => {
      if (isNumeric(arg)) {
        if (acc && Array.isArray(acc) && acc.length > arg) return acc[parseInt(arg)];
        return null;
      } else {
        if (acc && isObject(acc)) return acc[arg];
        return null;
      }
    }, state);
  };

  const handleState = (event, channel) => {
    // TODO: Handle different scopes and update elements based on scope.
    const detagged = event.data.slice(state_tag.length);
    const scope = detagged.split(':', 1)[0];
    const state = JSON.parse(detagged.slice(scope.length + 1));
    console.log(scope, state);
    Object.entries(channel.scopedElements(scope)).forEach(([ref, elements]) => {
        const value = reduceState(ref, state);
        console.log(ref, state);
        elements.forEach(element => element.innerHTML = transform(value, state, element));
    });
    channel.stateChangedCallbacks.forEach((callback) => {
        callback(scope, state);
    });
  };

  const handleEvent = (event, channel) => {
    const data = JSON.parse(event.data.slice(event_tag.length));
    if (Object.hasOwn(channel.invokeCallbacks, data.method)) {
      channel.invokeCallbacks[data.method].forEach(callback => {
        callback(data);
      });
    }
  };

  const handleAction = (event, channel) => {
    const data = JSON.parse(event.data.slice(actions_tag.length));
    data.actions.forEach(action => {
      channel.action_specs[action.name] = {
        callback: (...params) => {
          if (action.params.length != params.length) {
            throw new Error(`Invalid params for action '${action.name}'. Expected ${action.params.length} params, found ${params.length}`);
          }
          [...action.params].forEach((param, index) => {
            if (param.type !== typeof params[index]) {
              const err = `Incorrect argument type for argument ${index} in '${action.name}'. Expected: ${param.type}, found ${typeof params[index]}`;
              switch (param.type) {
                case "string":
                params[index] = `${params[index]}`;
                break;
                case "integer":
                try { params[index] = parseInt(params[index]) } catch {
                  throw new Error(err);
                };
                break;
                case "float":
                try { params[index] = parseFloat(params[index]) } catch {
                  throw new Error(err);
                };
                case "boolean":
                params[index] = ["true", "y", "1", "yes", "t", true].includes(params[index]);
                break;
                default:
                throw new Error(err);
              }
            }
          });
          channel.websocket.send(`_invoke:${action.name}:${JSON.stringify(params)}`);
        },
        spec: { ...action },
      };
      channel.actions[action.name] = channel.action_specs[action.name].callback;
    });

    document.querySelectorAll('[jetzig-click]').forEach(element => {
      const ref = element.getAttribute('jetzig-click');
      const action = channel.action_specs[ref];
      if (action) {
        element.addEventListener('click', () => {
          const args = [];
          action.spec.params.forEach(param => {
            const arg = element.dataset[param.name];
            if (arg === undefined) {
              throw new Error(`Expected 'data-${param.name}' attribute for '${action.name}' click handler.`);
            } else {
              args.push(element.dataset[param.name]);
            }
          });
          action.callback(...args);
        });
      } else {
        throw new Error(`Unknown click handler: '${ref}'`);
      }
    });
  };

  const initScopes = (channel) => {
    document.querySelectorAll('jetzig-scope').forEach(element => {
      channel.scopeWrappers.push(element);
    });
  };

  const initElementConnections = (channel) => {
    document.querySelectorAll('[jetzig-connect]').forEach(element => {
      const ref = element.getAttribute('jetzig-connect');
      const id = `jetzig-${crypto.randomUUID()}`;
      element.setAttribute('jetzig-id', id);
      channel.scopeWrappers.forEach(wrapper => {
        if (wrapper.compareDocumentPosition(element) & Node.DOCUMENT_POSITION_CONTAINED_BY) {
          if (!element.getAttribute('jetzig-scope')) element.setAttribute('jetzig-scope', wrapper.getAttribute('name'));
        }
      });
      const scope = element.getAttribute('jetzig-scope') || '__root__';
      if (!channel.elementMap[scope]) channel.elementMap[scope] = {};
      if (!channel.elementMap[scope][ref]) channel.elementMap[scope][ref] = [];
      channel.elementMap[scope][ref].push(element);
      const transformer = element.getAttribute('jetzig-transform');
      if (transformer) {
        channel.transformers[id] = new Function("value", "$", "element", `return ${transformer};`);
      }
    });
  };

  const initStyledElements = (channel) => {
  const styled_elements = document.querySelectorAll('[jetzig-style]');
    channel.onStateChanged(state => {
      styled_elements.forEach(element => {
        const func = new Function("$", `return ${element.getAttribute('jetzig-style')};`)
        const styles = func(state);
        Object.entries(styles).forEach(([key, value]) => {
          element.style.setProperty(key, value);
        });
      });
    });
  };

  const initWebsocket = (channel, host, path) => {
    channel.websocket = new WebSocket(`ws://${host}${path}`);
    channel.websocket.addEventListener("message", (event) => {
      if (event.data.startsWith(state_tag)) {
        handleState(event, channel);
      } else if (event.data.startsWith(event_tag)) {
        handleEvent(event, channel);
      } else if (event.data.startsWith(actions_tag)) {
        handleAction(event, channel);
      } else {
        const data = JSON.parse(event.data);
        channel.messageCallbacks.forEach((callback) => {
          callback(data);
        });
      }
    });
    channel.websocket.addEventListener("open", (event) => {
      // TODO
      channel.publish("websockets", {});
    });
  };

  Jetzig.channel = {
    websocket: null,
    actions: {},
    action_specs: {},
    stateChangedCallbacks: [],
    messageCallbacks: [],
    invokeCallbacks: {},
    elementMap: {},
    transformers: {},
    onStateChanged: function(callback) { this.stateChangedCallbacks.push(callback); },
    onMessage: function(callback) { this.messageCallbacks.push(callback); },
    scopedElements: function(scope) { return this.elementMap[scope] || {}; },
    scopeWrappers: [],
    init: function(host, path) {
      initScopes(this);
      initWebsocket(this, host, path);
      initElementConnections(this);
      initStyledElements(this);
    },
    receive: function(ref, callback) {
      if (Object.hasOwn(this.invokeCallbacks, ref)) {
        this.invokeCallbacks[ref].push(callback);
      } else {
        this.invokeCallbacks[ref] = [callback];
      }
    },
    publish: function(data) {
      if (this.websocket) {
        const json = JSON.stringify(data);
        this.websocket.send(json);
      }
    },
  };
})();
