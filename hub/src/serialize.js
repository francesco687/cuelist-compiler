'use strict';
// Tiny async mutex: chains tasks so they run one-at-a-time in call order.
// Each call returns the task's own promise; the chain survives task failures.
function createMutex() {
  let tail = Promise.resolve();
  return function run(task) {
    const result = tail.then(() => task());
    tail = result.then(() => {}, () => {});
    return result;
  };
}
module.exports = { createMutex };
