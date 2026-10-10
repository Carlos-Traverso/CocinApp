# Authentication demo

`AuthRepository` is the async contract used by the welcome screen, guards, and app shells. Its local adapter stores demo accounts and sessions in browser storage. Accounts created through the form get the `USER` role; a fixed demo path enters the UI as `ADMIN`.

This is not secure authentication or authorization. The role guard is only a frontend demo restriction, and demo credentials must not be real passwords. A future auth service should replace the adapter and enforce permissions server side.
