#!/bin/bash

# Mode 1 shows the battery temperature level on the IC display, as a purple indicator on the same menu as the energy graph
# Mode 2 does what 1 does, in addition to showing drive unit statistics on the left IC menu
# Can also be used to control other sdv commands such as GUI_developerMode (values= true and false for $MODE)
# From IC this command can be issued via curl -s "http://cid:4070/_data_set_value_request_?name=GUI_eggWotMode&value=$MODE"

KEY="GUI_eggWotMode"
STATE=$(lv $KEY | cut -d "\"" -f2)
WANTSTATE="Preparing"
MODE=1

echo "state is" $STATE
echo "state wanted is" $WANTSTATE

if ! [ "$STATE" = "$WANTSTATE" ]; then
  sdv $KEY $MODE
  echo "Enabling $KEY $MODE"
else
  echo "Already Enabled"
fi
