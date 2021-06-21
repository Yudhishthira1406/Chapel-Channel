## Channel Module

A channel is a FIFO data structure used to communicate between different Chapel tasks.
Since the operations on channel are blocking by default, it enables to send values from one task to another in a synchronized manner.

The module would comprise a class `Channel` to store the channel buffer and support operations on them.

The features inspired from the original Go Channels.
  
* Here are some functions that the module should have

	*  `send(value : eltType)` : This function waits for a space in the buffer and sends the `value` to the Channel.

	*  `recv() : eltType` : This function waits until the buffer is empty and returns the value sent to the Channel.

	*  `close()` : This function is used to close the channel such that no more values will be sent to it.

* `iter these()` : An iterator to receive the values sent to the channel until it is closed.

* `select` statements : This statement lets you wait for multiple channel operations and executes if anyone of them is ready for communication.

Some related questions -
*  Should this module be standard or package ?
*  What should be the name of the module ?
	 * proposal : `Channels`
* Should the Channel select be used with the Chapel [select](https://chapel-lang.org/docs/language/spec/statements.html#the-select-statement) syntax or something else?

