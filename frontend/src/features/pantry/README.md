# Pantry

`PantryRepository` provides async inventory reads and writes for the UI. The local mock validates stored records and uses browser storage. The receipt scanner is an async mock contract: it validates image type and the 5 MB limit, then returns editable sample rows without uploading or retaining the image. Stock changes only after the user confirms the reviewed proposal.
