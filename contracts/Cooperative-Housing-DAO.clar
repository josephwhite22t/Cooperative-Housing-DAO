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
