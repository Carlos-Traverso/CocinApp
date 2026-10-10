# Administration

Admin catalog pages use the asynchronous `AdminRepository` contract and a local validated mock. Required fields, duplicate names, dimensions, positive conversion multipliers, and references are checked before changes. Referenced catalog records use logical deletion.

The protected `/admin/users` page lists and searches accounts, creates user accounts, edits names, and activates or deactivates accounts. The demo administrator account is immutable. User management uses local demo data and does not change the demo authentication flow or connect to a server. Admin routes are guarded by the demo admin role in the frontend; this is a UI gate, not a server security control.
