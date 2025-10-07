(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_VOTING_ACTIVE (err u104))
(define-constant ERR_ALREADY_VOTED (err u105))
(define-constant ERR_INVALID_AMOUNT (err u106))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u107))
(define-constant ERR_ALREADY_EXECUTED (err u108))
(define-constant ERR_INSUFFICIENT_TOKENS (err u109))
(define-constant ERR_REPUTATION_OVERFLOW (err u200))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u201))
(define-constant REPUTATION_PROPOSAL_BONUS u10)
(define-constant REPUTATION_VOTE_BONUS u5)
(define-constant REPUTATION_CONTRIBUTION_MULTIPLIER u2)
(define-constant REPUTATION_DECAY_RATE u1)
(define-constant MAX_REPUTATION u10000)

(define-constant ACTIVITY_WINDOW u1008)
(define-constant MIN_ACTIONS_FOR_REWARD u3)
(define-constant ACTIVITY_TOKEN_REWARD u50)
(define-constant STREAK_BONUS_MULTIPLIER u2)
(define-constant MAX_STREAK_BONUS u200)

(define-constant ERR_DISPUTE_NOT_FOUND (err u300))
(define-constant ERR_CANNOT_DISPUTE_SELF (err u301))
(define-constant ERR_DISPUTE_ALREADY_EXISTS (err u302))
(define-constant ERR_DISPUTE_RESOLVED (err u303))
(define-constant ERR_INVALID_PENALTY_AMOUNT (err u304))
(define-constant DISPUTE_VOTING_PERIOD u144)
(define-constant MAX_PENALTY_PERCENTAGE u20)

(define-constant ERR_SELF_DELEGATION (err u400))
(define-constant ERR_NO_DELEGATION_FOUND (err u401))

(define-data-var dispute-counter uint u0)

(define-fungible-token housing-token)

(define-data-var total-supply uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var treasury-balance uint u0)

(define-map token-holders principal uint)
(define-map proposals uint {
    id: uint,
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    amount: uint,
    proposal-type: (string-ascii 20),
    votes-for: uint,
    votes-against: uint,
    start-block: uint,
    end-block: uint,
    executed: bool,
    passed: bool
})

(define-map votes {proposal-id: uint, voter: principal} {vote: bool, amount: uint})
(define-map member-contributions principal uint)

(define-public (initialize-dao (initial-supply uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (try! (ft-mint? housing-token initial-supply tx-sender))
        (var-set total-supply initial-supply)
        (map-set token-holders tx-sender initial-supply)
        (ok true)
    )
)

(define-public (transfer-tokens (amount uint) (recipient principal))
    (let ((sender-balance (default-to u0 (map-get? token-holders tx-sender))))
        (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
        (try! (ft-transfer? housing-token amount tx-sender recipient))
        (map-set token-holders tx-sender (- sender-balance amount))
        (map-set token-holders recipient (+ (default-to u0 (map-get? token-holders recipient)) amount))
        (ok true)
    )
)

(define-public (contribute-to-treasury (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (map-set member-contributions tx-sender (+ (default-to u0 (map-get? member-contributions tx-sender)) amount))
        (ok true)
    )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (amount uint) (proposal-type (string-ascii 20)))
    (let ((proposal-id (+ (var-get proposal-counter) u1))
          (token-balance (default-to u0 (map-get? token-holders tx-sender))))
        (asserts! (> token-balance u0) ERR_INSUFFICIENT_TOKENS)
        (map-set proposals proposal-id {
            id: proposal-id,
            proposer: tx-sender,
            title: title,
            description: description,
            amount: amount,
            proposal-type: proposal-type,
            votes-for: u0,
            votes-against: u0,
            start-block: stacks-block-height,
            end-block: (+ stacks-block-height u144),
            executed: false,
            passed: false
        })
        (var-set proposal-counter proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
          (voter-tokens (default-to u0 (map-get? token-holders tx-sender)))
          (vote-key {proposal-id: proposal-id, voter: tx-sender}))
        (asserts! (> voter-tokens u0) ERR_INSUFFICIENT_TOKENS)
        (asserts! (<= stacks-block-height (get end-block proposal)) ERR_VOTING_ENDED)
        (asserts! (is-none (map-get? votes vote-key)) ERR_ALREADY_VOTED)
        
        (map-set votes vote-key {vote: vote-for, amount: voter-tokens})
        
        (if vote-for
            (map-set proposals proposal-id (merge proposal {votes-for: (+ (get votes-for proposal) voter-tokens)}))
            (map-set proposals proposal-id (merge proposal {votes-against: (+ (get votes-against proposal) voter-tokens)}))
        )
        (ok true)
    )
)

(define-public (finalize-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND)))
        (asserts! (> stacks-block-height (get end-block proposal)) ERR_VOTING_ACTIVE)
        (asserts! (not (get executed proposal)) ERR_ALREADY_EXECUTED)
        
        (let ((total-votes (+ (get votes-for proposal) (get votes-against proposal)))
              (passed (and (> total-votes (/ (var-get total-supply) u2))
                          (> (get votes-for proposal) (get votes-against proposal)))))
            (map-set proposals proposal-id (merge proposal {passed: passed}))
            (ok passed)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND)))
        (asserts! (get passed proposal) ERR_PROPOSAL_NOT_PASSED)
        (asserts! (not (get executed proposal)) ERR_ALREADY_EXECUTED)
        (asserts! (>= (var-get treasury-balance) (get amount proposal)) ERR_INSUFFICIENT_BALANCE)
        
        (if (is-eq (get proposal-type proposal) "repair")
            (begin
                (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get proposer proposal))))
                (var-set treasury-balance (- (var-get treasury-balance) (get amount proposal)))
                (map-set proposals proposal-id (merge proposal {executed: true}))
                (ok true)
            )
            (if (is-eq (get proposal-type proposal) "improvement")
                (begin
                    (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get proposer proposal))))
                    (var-set treasury-balance (- (var-get treasury-balance) (get amount proposal)))
                    (map-set proposals proposal-id (merge proposal {executed: true}))
                    (ok true)
                )
                (begin
                    (map-set proposals proposal-id (merge proposal {executed: true}))
                    (ok true)
                )
            )
        )
    )
)

(define-public (distribute-profits (total-profit uint))
    (let ((token-balance (default-to u0 (map-get? token-holders tx-sender)))
          (user-share (/ (* total-profit token-balance) (var-get total-supply))))
        (asserts! (> token-balance u0) ERR_INSUFFICIENT_TOKENS)
        (asserts! (>= (var-get treasury-balance) user-share) ERR_INSUFFICIENT_BALANCE)
        (try! (as-contract (stx-transfer? user-share tx-sender tx-sender)))
        (var-set treasury-balance (- (var-get treasury-balance) user-share))
        (ok user-share)
    )
)

(define-public (emergency-withdraw)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (let ((balance (var-get treasury-balance)))
            (try! (as-contract (stx-transfer? balance tx-sender CONTRACT_OWNER)))
            (var-set treasury-balance u0)
            (ok balance)
        )
    )
)

(define-read-only (get-token-balance (user principal))
    (default-to u0 (map-get? token-holders user))
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)

(define-read-only (get-total-supply)
    (var-get total-supply)
)

(define-read-only (get-member-contribution (member principal))
    (default-to u0 (map-get? member-contributions member))
)

(define-read-only (get-proposal-count)
    (var-get proposal-counter)
)

(define-read-only (calculate-voting-power (user principal))
    (let ((tokens (default-to u0 (map-get? token-holders user)))
          (total (var-get total-supply)))
        (if (> total u0)
            (/ (* tokens u10000) total)
            u0
        )
    )
)


(define-map member-reputation principal uint)
(define-map reputation-actions principal {
    proposals-created: uint,
    votes-cast: uint,
    last-activity-block: uint
})

(define-public (award-reputation (member principal) (points uint))
    (let ((current-reputation (default-to u0 (map-get? member-reputation member))))
        (asserts! (<= (+ current-reputation points) MAX_REPUTATION) ERR_REPUTATION_OVERFLOW)
        (map-set member-reputation member (+ current-reputation points))
        (ok (+ current-reputation points))
    )
)

(define-public (deduct-reputation (member principal) (points uint))
    (let ((current-reputation (default-to u0 (map-get? member-reputation member))))
        (if (>= current-reputation points)
            (begin
                (map-set member-reputation member (- current-reputation points))
                (ok (- current-reputation points))
            )
            (begin
                (map-set member-reputation member u0)
                (ok u0)
            )
        )
    )
)

(define-public (update-reputation-for-proposal (proposer principal))
    (let ((actions (default-to {proposals-created: u0, votes-cast: u0, last-activity-block: u0}
                               (map-get? reputation-actions proposer))))
        (map-set reputation-actions proposer (merge actions {
            proposals-created: (+ (get proposals-created actions) u1),
            last-activity-block: stacks-block-height
        }))
        (award-reputation proposer REPUTATION_PROPOSAL_BONUS)
    )
)

(define-public (update-reputation-for-vote (voter principal))
    (let ((actions (default-to {proposals-created: u0, votes-cast: u0, last-activity-block: u0}
                               (map-get? reputation-actions voter))))
        (map-set reputation-actions voter (merge actions {
            votes-cast: (+ (get votes-cast actions) u1),
            last-activity-block: stacks-block-height
        }))
        (award-reputation voter REPUTATION_VOTE_BONUS)
    )
)

(define-public (update-reputation-for-contribution (contributor principal) (amount uint))
    (let ((reputation-points (/ amount u1000000)))
        (if (> reputation-points u0)
            (award-reputation contributor (* reputation-points REPUTATION_CONTRIBUTION_MULTIPLIER))
            (ok u0)
        )
    )
)

(define-public (apply-reputation-decay (member principal))
    (let ((actions (map-get? reputation-actions member)))
        (match actions
            member-actions
            (if (> (- stacks-block-height (get last-activity-block member-actions)) u1000)
                (deduct-reputation member REPUTATION_DECAY_RATE)
                (ok (default-to u0 (map-get? member-reputation member)))
            )
            (ok u0)
        )
    )
)

(define-read-only (get-member-reputation (member principal))
    (default-to u0 (map-get? member-reputation member))
)

(define-read-only (get-reputation-multiplier (member principal))
    (let ((reputation (default-to u0 (map-get? member-reputation member))))
        (+ u100 (/ reputation u100))
    )
)

(define-read-only (get-member-actions (member principal))
    (default-to {proposals-created: u0, votes-cast: u0, last-activity-block: u0}
                (map-get? reputation-actions member))
)

(define-read-only (calculate-reputation-weighted-voting-power (member principal))
    (let ((base-tokens (default-to u0 (map-get? token-holders member)))
          (reputation-multiplier (get-reputation-multiplier member)))
        (/ (* base-tokens reputation-multiplier) u100)
    )
)


(define-map member-activity principal {
    current-window-start: uint,
    actions-this-window: uint,
    consecutive-active-windows: uint,
    total-rewards-earned: uint
})

(define-public (track-member-action (member principal))
    (let ((current-window-start (/ stacks-block-height ACTIVITY_WINDOW))
          (activity (default-to {current-window-start: u0, actions-this-window: u0, 
                                consecutive-active-windows: u0, total-rewards-earned: u0}
                               (map-get? member-activity member))))
        (if (is-eq (get current-window-start activity) current-window-start)
            (map-set member-activity member (merge activity {
                actions-this-window: (+ (get actions-this-window activity) u1)
            }))
            (let ((was-active (>= (get actions-this-window activity) MIN_ACTIONS_FOR_REWARD))
                  (new-streak (if was-active 
                                (+ (get consecutive-active-windows activity) u1) 
                                u0)))
                (map-set member-activity member {
                    current-window-start: current-window-start,
                    actions-this-window: u1,
                    consecutive-active-windows: new-streak,
                    total-rewards-earned: (get total-rewards-earned activity)
                })
            )
        )
        (ok true)
    )
)

(define-public (claim-activity-reward)
    (let ((current-window-start (/ stacks-block-height ACTIVITY_WINDOW))
          (activity (unwrap! (map-get? member-activity tx-sender) ERR_NOT_AUTHORIZED)))
        (asserts! (< (get current-window-start activity) current-window-start) ERR_VOTING_ACTIVE)
        (asserts! (>= (get actions-this-window activity) MIN_ACTIONS_FOR_REWARD) ERR_INSUFFICIENT_TOKENS)
        
        (let ((base-reward ACTIVITY_TOKEN_REWARD)
              (calculated-bonus (* (get consecutive-active-windows activity) STREAK_BONUS_MULTIPLIER))
              (streak-bonus (if (> calculated-bonus MAX_STREAK_BONUS) MAX_STREAK_BONUS calculated-bonus))
              (total-reward (+ base-reward streak-bonus)))
            (try! (ft-mint? housing-token total-reward tx-sender))
            (var-set total-supply (+ (var-get total-supply) total-reward))
            (map-set token-holders tx-sender (+ (get-token-balance tx-sender) total-reward))
            (map-set member-activity tx-sender (merge activity {
                total-rewards-earned: (+ (get total-rewards-earned activity) total-reward)
            }))
            (ok total-reward)
        )
    )
)

(define-read-only (get-member-activity (member principal))
    (default-to {current-window-start: u0, actions-this-window: u0, 
                consecutive-active-windows: u0, total-rewards-earned: u0}
               (map-get? member-activity member))
)

(define-read-only (calculate-pending-reward (member principal))
    (let ((activity (get-member-activity member))
          (current-window (/ stacks-block-height ACTIVITY_WINDOW)))
        (if (and (< (get current-window-start activity) current-window)
                (>= (get actions-this-window activity) MIN_ACTIONS_FOR_REWARD))
            (let ((calculated-bonus (* (get consecutive-active-windows activity) STREAK_BONUS_MULTIPLIER)))
                (+ ACTIVITY_TOKEN_REWARD 
                   (if (> calculated-bonus MAX_STREAK_BONUS) MAX_STREAK_BONUS calculated-bonus)))
            u0
        )
    )
)

(define-read-only (get-activity-window-progress)
    (let ((current-block stacks-block-height)
          (window-start (* (/ current-block ACTIVITY_WINDOW) ACTIVITY_WINDOW)))
        {
            blocks-into-window: (- current-block window-start),
            blocks-remaining: (- ACTIVITY_WINDOW (- current-block window-start)),
            window-number: (/ current-block ACTIVITY_WINDOW)
        }
    )
)


(define-map disputes uint {
    id: uint,
    complainant: principal,
    accused: principal,
    category: (string-ascii 20),
    description: (string-ascii 300),
    penalty-amount: uint,
    votes-guilty: uint,
    votes-innocent: uint,
    end-block: uint,
    resolved: bool,
    guilty: bool
})

(define-map dispute-votes {dispute-id: uint, voter: principal} bool)



(define-public (file-dispute (accused principal) (category (string-ascii 20)) (description (string-ascii 300)) (penalty-amount uint))
    (let ((dispute-id (+ (var-get dispute-counter) u1))
          (complainant-balance (get-token-balance tx-sender))
          (max-penalty (/ (* complainant-balance MAX_PENALTY_PERCENTAGE) u100)))
        (asserts! (not (is-eq tx-sender accused)) ERR_CANNOT_DISPUTE_SELF)
        (asserts! (> complainant-balance u0) ERR_INSUFFICIENT_TOKENS)
        (asserts! (<= penalty-amount max-penalty) ERR_INVALID_PENALTY_AMOUNT)

        
        (map-set disputes dispute-id {
            id: dispute-id,
            complainant: tx-sender,
            accused: accused,
            category: category,
            description: description,
            penalty-amount: penalty-amount,
            votes-guilty: u0,
            votes-innocent: u0,
            end-block: (+ stacks-block-height DISPUTE_VOTING_PERIOD),
            resolved: false,
            guilty: false
        })
        (var-set dispute-counter dispute-id)
        (ok dispute-id)
    )
)

(define-public (vote-on-dispute (dispute-id uint) (guilty-vote bool))
    (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
          (voter-tokens (get-token-balance tx-sender))
          (vote-key {dispute-id: dispute-id, voter: tx-sender}))
        (asserts! (> voter-tokens u0) ERR_INSUFFICIENT_TOKENS)
        (asserts! (<= stacks-block-height (get end-block dispute)) ERR_VOTING_ENDED)
        (asserts! (not (get resolved dispute)) ERR_DISPUTE_RESOLVED)
        (asserts! (is-none (map-get? dispute-votes vote-key)) ERR_ALREADY_VOTED)
        
        (map-set dispute-votes vote-key guilty-vote)
        (if guilty-vote
            (map-set disputes dispute-id (merge dispute {votes-guilty: (+ (get votes-guilty dispute) voter-tokens)}))
            (map-set disputes dispute-id (merge dispute {votes-innocent: (+ (get votes-innocent dispute) voter-tokens)}))
        )
        (ok true)
    )
)

(define-public (resolve-dispute (dispute-id uint))
    (let ((dispute (unwrap! (map-get? disputes dispute-id) ERR_DISPUTE_NOT_FOUND))
          (total-votes (+ (get votes-guilty dispute) (get votes-innocent dispute))))
        (asserts! (> stacks-block-height (get end-block dispute)) ERR_VOTING_ACTIVE)
        (asserts! (not (get resolved dispute)) ERR_DISPUTE_RESOLVED)
        (asserts! (> total-votes (/ (var-get total-supply) u4)) ERR_INSUFFICIENT_TOKENS)
        
        (let ((is-guilty (> (get votes-guilty dispute) (get votes-innocent dispute))))
            (map-set disputes dispute-id (merge dispute {resolved: true, guilty: is-guilty}))
            (if (and is-guilty (> (get penalty-amount dispute) u0))
                (begin
                    (try! (transfer-tokens (get penalty-amount dispute) (get complainant dispute)))
                    (ok {resolved: true, guilty: is-guilty, penalty-applied: (get penalty-amount dispute)})
                )
                (ok {resolved: true, guilty: is-guilty, penalty-applied: u0})
            )
        )
    )
)

(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes dispute-id)
)

(define-read-only (get-dispute-vote (dispute-id uint) (voter principal))
    (map-get? dispute-votes {dispute-id: dispute-id, voter: voter})
)

(define-read-only (get-active-dispute (complainant principal) (accused principal))
    none
)

(define-read-only (get-dispute-count)
    (var-get dispute-counter)
)


(define-map delegations principal principal)
(define-map delegation-power principal uint)

(define-public (delegate-voting-power (delegate principal))
    (let ((delegator-tokens (get-token-balance tx-sender))
          (current-delegate (map-get? delegations tx-sender)))
        (asserts! (not (is-eq tx-sender delegate)) ERR_SELF_DELEGATION)
        (asserts! (> delegator-tokens u0) ERR_INSUFFICIENT_TOKENS)
        
        (match current-delegate
            old-delegate
            (map-set delegation-power old-delegate 
                (- (default-to u0 (map-get? delegation-power old-delegate)) delegator-tokens))
            true
        )
        
        (map-set delegations tx-sender delegate)
        (map-set delegation-power delegate 
            (+ (default-to u0 (map-get? delegation-power delegate)) delegator-tokens))
        (ok true)
    )
)

(define-public (revoke-delegation)
    (let ((delegator-tokens (get-token-balance tx-sender))
          (current-delegate (unwrap! (map-get? delegations tx-sender) ERR_NO_DELEGATION_FOUND)))
        (map-delete delegations tx-sender)
        (map-set delegation-power current-delegate 
            (- (default-to u0 (map-get? delegation-power current-delegate)) delegator-tokens))
        (ok true)
    )
)

(define-read-only (get-delegation (delegator principal))
    (map-get? delegations delegator)
)

(define-read-only (get-delegated-power (delegate principal))
    (default-to u0 (map-get? delegation-power delegate))
)

(define-read-only (get-total-voting-power (member principal))
    (+ (get-token-balance member) (get-delegated-power member))
)

(define-read-only (has-delegated (member principal))
    (is-some (map-get? delegations member))
)

(define-read-only (calculate-delegate-influence (delegate principal))
    (let ((total-power (get-total-voting-power delegate))
          (supply (var-get total-supply)))
        (if (> supply u0)
            (/ (* total-power u10000) supply)
            u0
        )
    )
)