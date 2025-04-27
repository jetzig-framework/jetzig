window.jetzig = window.jetzig ? window.jetzig : {}
jetzig = window.jetzig;

(() => {
  const transform = (value, state, element) => {
      const id = element.getAttribute('jetzig-id');
      const key = id && jetzig.channel.transformerMap[id];
      const transformers = key && jetzig.channel.transformers[key];
      if (transformers) {
          return transformers.reduce((acc, val) => val(acc), value);
      } else {
          return value === undefined || value == null ? '' : `${value}`
      }
  };

  jetzig.channel = {
      websocket: null,
      actions: {},
      stateChangedCallbacks: [],
      messageCallbacks: [],
      invokeCallbacks: {},
      elementMap: {},
      transformerMap: {},
      transformers: {},
      onStateChanged: function(callback) { this.stateChangedCallbacks.push(callback); },
      onMessage: function(callback) { this.messageCallbacks.push(callback); },
      init: function(host, path) {
          console.log("here");
          this.websocket = new WebSocket(`ws://${host}${path}`);
          this.websocket.addEventListener("message", (event) => {
              const state_tag = "__jetzig_channel_state__:";
              const actions_tag = "__jetzig_actions__:";
              const event_tag = "__jetzig_event__:";

              if (event.data.startsWith(state_tag)) {
                  const state = JSON.parse(event.data.slice(state_tag.length));
                  Object.entries(this.elementMap).forEach(([ref, elements]) => {
                      const value = reduceState(ref, state);
                      elements.forEach(element => element.innerHTML = transform(value, state, element));
                  });
                  this.stateChangedCallbacks.forEach((callback) => {
                      callback(state);
                  });
              } else if (event.data.startsWith(event_tag)) {
                  const data = JSON.parse(event.data.slice(event_tag.length));
                  if (Object.hasOwn(this.invokeCallbacks, data.method)) {
                      this.invokeCallbacks[data.method].forEach(callback => {
                          callback(data);
                      });
                  }
              } else if (event.data.startsWith(actions_tag)) {
                  const data = JSON.parse(event.data.slice(actions_tag.length));
                  data.actions.forEach(action => {
                      this.actions[action.name] = {
                          callback: (...params) => {
                            if (action.params.length != params.length) {
                                throw new Error(`Invalid params for action '${action.name}'`);
                            }
                            [...action.params].forEach((param, index) => {
                                const map = {
                                    s: "string",
                                    b: "boolean",
                                    i: "number",
                                    f: "number",
                                };
                                if (map[param] !== typeof params[index]) {
                                    throw new Error(`Incorrect argument type for argument ${index} in '${action.name}'. Expected: ${map[param]}, found ${typeof params[index]}`);
                                }
                            });

                            this.websocket.send(`_invoke:${action.name}:${JSON.stringify(params)}`);
                          },
                      spec: { ...action },
                    };
                  });
                  console.log(this.actions);
              } else {
                  const data = JSON.parse(event.data);
                  this.messageCallbacks.forEach((callback) => {
                      callback(data);
                  });
              }

          });

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

          document.querySelectorAll('[jetzig-connect]').forEach(element => {
              const ref = element.getAttribute('jetzig-connect');
              if (!this.elementMap[ref]) this.elementMap[ref] = [];
              const id = `jetzig-${crypto.randomUUID()}`;
              element.setAttribute('jetzig-id', id);
              this.elementMap[ref].push(element);
              this.transformerMap[id] = element.getAttribute('jetzig-transform');
          });
          document.querySelectorAll('[jetzig-click]').forEach(element => {
              const ref = element.getAttribute('jetzig-click');
              const action = this.actions[ref];
              if (action) {
                
              }
          });

          // this.websocket.addEventListener("open", (event) => {
          //     // TODO
          //     this.publish("websockets", {});
          // });
      },
      transform: function(ref, callback) {
          if (Object.hasOwn(this.transformers, ref)) {
              this.transformers[ref].push(callback);
          } else {
              this.transformers[ref] = [callback];
          }
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
