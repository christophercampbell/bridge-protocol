------------------------------ MODULE bridge ------------------------------
EXTENDS Integers, Sequences, TLC

(****************************************************************
 Process Actors
****************************************************************)
Sender   == "Sender"
Receiver == "Receiver"
Contract == "Contract"
Events   == "Events"
Store    == "Store"

(****************************************************************
 Process Counters and machine states
****************************************************************)
VARIABLES pc,
          contractState,
          storeState,
          eventsMessage,
          senderNotified,
          receiverNotified

(****************************************************************
 Initialize process counters and states
****************************************************************)
Init ==
    /\ pc = [
         Sender   |-> "S_BEGIN",
         Receiver |-> "R_WAIT_NOTIFICATION",
         Contract |-> "C_WAIT_FOR_BRIDGE",
         Events   |-> "E_WAIT_BRIDGE",
         Store    |-> "S_MONITOR"
       ]
    /\ contractState = "Initial"
    /\ storeState = "Empty"
    /\ eventsMessage = << >>
    /\ senderNotified = FALSE
    /\ receiverNotified = FALSE

(****************************************************************
 ACTIONS are written as sub-actions. The general pattern:
    1) A condition that pc["Process"] = "StepLabel"
    2) Additional enabling conditions if required
    3) Update variables
    4) pc' updated to the next step label
****************************************************************)

\* ------------------------ Sender ACTIONS ------------------------
S_BEGIN_Act ==
    /\ pc[Sender] = "S_BEGIN"
    \* (No extra conditions, can move on immediately)
    /\ pc' = [ pc EXCEPT ![Sender] = "S_WAIT_NOTIFICATION_2" ]
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified, pc[Receiver], pc[Contract], pc[Events], pc[Store] >>

S_WAIT_NOTIFICATION_2_Act ==
    /\ pc[Sender] = "S_WAIT_NOTIFICATION_2"
    /\ senderNotified = TRUE
    \* Once senderNotified=TRUE, proceed
    /\ pc' = [ pc EXCEPT ![Sender] = "S_DONE" ]
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified, pc[Receiver], pc[Contract], pc[Events], pc[Store] >>

S_DONE_Act ==
    /\ pc[Sender] = "S_DONE"
    \* "Done" => stutter
    /\ pc' = pc
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified >>

\* ------------------------ receiver ACTIONS ------------------------
R_WAIT_NOTIFICATION_Act ==
    /\ pc[Receiver] = "R_WAIT_NOTIFICATION"
    /\ receiverNotified = TRUE
    /\ pc' = [ pc EXCEPT ![Receiver] = "R_CLAIM_ASSET" ]
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified, pc[Sender], pc[Contract], pc[Events], pc[Store] >>

R_CLAIM_ASSET_Act ==
    /\ pc[Receiver] = "R_CLAIM_ASSET"
    \* Next step
    /\ pc' = [ pc EXCEPT ![Receiver] = "R_DONE" ]
    /\ UNCHANGED <<
         contractState, storeState, eventsMessage, senderNotified, receiverNotified,
         pc[Sender], pc[Contract], pc[Events], pc[Store]
       >>

R_DONE_Act ==
    /\ pc[Receiver] = "R_DONE"
    /\ pc' = pc
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified >>

\* ----------------------- CONTRACT ACTIONS -----------------------
C_WAIT_FOR_BRIDGE_Act ==
    /\ pc[Contract] = "C_WAIT_FOR_BRIDGE"
    /\ contractState = "Initial"
    /\ pc' = [ pc EXCEPT ![Contract] = "C_WAIT_FOR_CLAIM" ]
    /\ contractState' = "Bridging"
    /\ eventsMessage' = Append(eventsMessage, "bridgeMessage")
    /\ storeState' = "UpdatedByBridge"
    /\ UNCHANGED << senderNotified, receiverNotified, pc[Sender], pc[Receiver], pc[Events], pc[Store] >>

C_WAIT_FOR_CLAIM_Act ==
    /\ pc[Contract] = "C_WAIT_FOR_CLAIM"
    /\ storeState = "UpdatedByBridge"
    /\ eventsMessage = << >>
    /\ receiverNotified = TRUE
    \* After bridging is done and receiver is notified, proceed
    /\ pc' = [ pc EXCEPT ![Contract] = "C_DONE" ]
    /\ contractState' = "Claiming"
    /\ eventsMessage' = Append(eventsMessage, "claimMessage")
    /\ storeState' = "UpdatedByClaim"
    /\ UNCHANGED << senderNotified, receiverNotified, pc[Sender], pc[Receiver], pc[Events], pc[Store] >>

C_DONE_Act ==
    /\ pc[Contract] = "C_DONE"
    /\ pc' = pc
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified >>

\* ----------------------- EVENTS ACTIONS -----------------------
E_WAIT_BRIDGE_Act ==
    /\ pc[Events] = "E_WAIT_BRIDGE"
    /\ eventsMessage = << >> \/ eventsMessage = << "bridgeMessage" >>
    /\ LET doBridge ==
         IF eventsMessage = << "bridgeMessage" >>
         THEN /\ eventsMessage' = << >>
              /\ receiverNotified' = TRUE
         ELSE /\ eventsMessage' = eventsMessage
              /\ receiverNotified' = receiverNotified
       IN
         /\ pc' = [ pc EXCEPT ![Events] = "E_WAIT_CLAIM" ]
         /\ doBridge
         /\ UNCHANGED << contractState, storeState, senderNotified, pc[Sender], pc[Receiver], pc[Contract], pc[Store] >>

E_WAIT_CLAIM_Act ==
    /\ pc[Events] = "E_WAIT_CLAIM"
    /\ eventsMessage = << >> \/ eventsMessage = << "claimMessage" >>
    /\ LET doClaim ==
         IF eventsMessage = << "claimMessage" >>
         THEN /\ eventsMessage' = << >>
              /\ senderNotified' = TRUE
         ELSE /\ eventsMessage' = eventsMessage
              /\ senderNotified' = senderNotified
       IN
         /\ pc' = [ pc EXCEPT ![Events] = "E_DONE" ]
         /\ doClaim
         /\ UNCHANGED << contractState, storeState, receiverNotified, pc[Sender], pc[Receiver], pc[Contract], pc[Store] >>

E_DONE_Act ==
    /\ pc[Events] = "E_DONE"
    /\ pc' = pc
    /\ UNCHANGED << contractState, storeState, eventsMessage, senderNotified, receiverNotified >>

\* ----------------------- STORE ACTIONS -----------------------
S_MONITOR_Act ==
    /\ pc[Store] = "S_MONITOR"
    \* Just stutter forever for the store
    /\ pc' = pc
    /\ UNCHANGED <<contractState, storeState, eventsMessage, senderNotified, receiverNotified>>

(****************************************************************
 Next is the disjunction of all sub-actions. In each state step, 
 exactly one sub-action can fire (unless concurrency is possible).
****************************************************************)
Next ==
    \* sender steps
    S_BEGIN_Act
    \/ S_WAIT_NOTIFICATION_2_Act
    \/ S_DONE_Act

    \* receiver steps
    \/ R_WAIT_NOTIFICATION_Act
    \/ R_CLAIM_ASSET_Act
    \/ R_DONE_Act

    \* Contract steps
    \/ C_WAIT_FOR_BRIDGE_Act
    \/ C_WAIT_FOR_CLAIM_Act
    \/ C_DONE_Act

    \* Events steps
    \/ E_WAIT_BRIDGE_Act
    \/ E_WAIT_CLAIM_Act
    \/ E_DONE_Act

    \* Store steps
    \/ S_MONITOR_Act

(****************************************************************
 The overall spec: Start in Init, and then always take Next.
****************************************************************)
vars == <<pc, contractState, storeState, eventsMessage, senderNotified, receiverNotified >>

Spec == Init /\ [][Next]_vars

(****************************************************************
 Next step is to add invariants, fairness, etc. For now, 
 "Spec" is sufficient to run a basic model check in TLC.
****************************************************************)

==============================================================================
