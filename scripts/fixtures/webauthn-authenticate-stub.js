export const webauthnTestState = {
  authenticateCalls: [],
  returnSuccessCalls: [],
  signalCalls: 0,
};

let authenticateImplementation = () => undefined;

export function resetWebauthnTestState() {
  webauthnTestState.authenticateCalls = [];
  webauthnTestState.returnSuccessCalls = [];
  webauthnTestState.signalCalls = 0;
  authenticateImplementation = () => undefined;
}

export function setAuthenticateImplementation(implementation) {
  authenticateImplementation = implementation;
}

export function doAuthenticate(options) {
  webauthnTestState.authenticateCalls.push(options);
  return authenticateImplementation(options);
}
export function getAllowCredentials() { return []; }
export function returnSuccess(result) { webauthnTestState.returnSuccessCalls.push(result); }
export function signal() {
  webauthnTestState.signalCalls += 1;
  return new AbortController().signal;
}
