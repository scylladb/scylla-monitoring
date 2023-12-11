System Overload
---------------

There could be multiple indications that a system is overloaded:

* Timeouts
* Requests shed - Requests are shed (dropped) when the system cannot process requests fast enough.
* CPU at 100% when no background process (like compaction or repair) runs.
* Queues are getting filled.

If you ruled out data-model problems and hardware failure, this could indicate you need to scale the system.

