;; Quantum Lottery - Decentralized Lottery on Stacks

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-active (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-no-winner (err u104))
(define-constant err-already-claimed (err u105))
(define-constant err-not-winner (err u106))
(define-constant err-not-ended (err u107))
(define-constant err-invalid-id (err u108))
(define-constant err-max-exceeded (err u109))

;; Data Variables
(define-data-var lottery-counter uint u0)
(define-data-var ticket-price uint u1000000)
(define-data-var platform-fee uint u5)
(define-data-var paused bool false)
(define-data-var current-block uint u0)

;; Data Maps
(define-map lotteries
    uint 
    {
        start: uint,
        end: uint,
        tickets-sold: uint,
        prize-pool: uint,
        completed: bool
    }
)

(define-map tickets
    { lottery: uint, number: uint }
    principal
)

(define-map user-ticket-count
    { lottery: uint, user: principal }
    uint
)

(define-map winners
    { lottery: uint, position: uint }
    { user: principal, amount: uint, claimed: bool }
)

;; Private Functions
(define-private (min (a uint) (b uint))
    (if (< a b) a b)
)

(define-private (get-pseudo-random (seed uint) (max uint))
    (+ (mod seed max) u1)
)

;; Read Only Functions
(define-read-only (get-lottery (id uint))
    (map-get? lotteries id)
)

(define-read-only (get-ticket-holder (lottery uint) (number uint))
    (map-get? tickets { lottery: lottery, number: number })
)

(define-read-only (get-user-ticket-balance (lottery uint) (user principal))
    (default-to u0 (map-get? user-ticket-count { lottery: lottery, user: user }))
)

(define-read-only (get-winner (lottery uint) (position uint))
    (map-get? winners { lottery: lottery, position: position })
)

(define-read-only (get-current-id)
    (var-get lottery-counter)
)

(define-read-only (is-paused)
    (var-get paused)
)

;; Public Functions
(define-public (create-lottery (duration uint))
    (let
        (
            (id (+ (var-get lottery-counter) u1))
            (start-at (var-get current-block))
            (end-at (+ start-at duration))
        )
        (asserts! (not (var-get paused)) err-not-active)
        (asserts! (> duration u0) err-invalid-amount)
        (asserts! (<= duration u4320) err-invalid-amount)
        
        (map-set lotteries id {
            start: start-at,
            end: end-at,
            tickets-sold: u0,
            prize-pool: u0,
            completed: false
        })
        
        (var-set lottery-counter id)
        (ok id)
    )
)

(define-public (buy-ticket (lottery-id uint) (amount uint))
    (let
        (
            (lottery (unwrap! (map-get? lotteries lottery-id) err-invalid-id))
            (total (* amount (var-get ticket-price)))
            (current-tickets (get tickets-sold lottery))
            (user-current (get-user-ticket-balance lottery-id tx-sender))
            (new-total (+ user-current amount))
        )
        (asserts! (not (var-get paused)) err-not-active)
        (asserts! (not (get completed lottery)) err-not-active)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= amount u10) err-invalid-amount)
        (asserts! (<= new-total u100) err-max-exceeded)
        (asserts! (>= (stx-get-balance tx-sender) total) err-insufficient-funds)
        
        ;; Transfer payment
        (try! (stx-transfer? total tx-sender (as-contract tx-sender)))
        
        ;; Register tickets
        (map-set tickets { lottery: lottery-id, number: (+ current-tickets u1) } tx-sender)
        (if (> amount u1) (map-set tickets { lottery: lottery-id, number: (+ current-tickets u2) } tx-sender) true)
        (if (> amount u2) (map-set tickets { lottery: lottery-id, number: (+ current-tickets u3) } tx-sender) true)
        (if (> amount u3) (map-set tickets { lottery: lottery-id, number: (+ current-tickets u4) } tx-sender) true)
        (if (> amount u4) (map-set tickets { lottery: lottery-id, number: (+ current-tickets u5) } tx-sender) true)
        
        ;; Update lottery state
        (map-set lotteries lottery-id 
            (merge lottery {
                tickets-sold: (+ current-tickets amount),
                prize-pool: (+ (get prize-pool lottery) total)
            })
        )
        
        ;; Update user count
        (map-set user-ticket-count { lottery: lottery-id, user: tx-sender } new-total)
        
        (ok amount)
    )
)

(define-public (draw-winners (lottery-id uint) (seed uint))
    (let
        (
            (lottery (unwrap! (map-get? lotteries lottery-id) err-invalid-id))
            (total-tickets (get tickets-sold lottery))
            (prize-pool (get prize-pool lottery))
            (first-prize (/ (* prize-pool u50) u100))
            (second-prize (/ (* prize-pool u30) u100))
            (third-prize (/ (* prize-pool u20) u100))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (get completed lottery)) err-already-claimed)
        (asserts! (> total-tickets u2) err-no-winner)
        
        ;; Select winners
        (let
            (
                (winner1-num (get-pseudo-random seed total-tickets))
                (winner2-num (get-pseudo-random (+ seed u999) total-tickets))
                (winner3-num (get-pseudo-random (+ seed u1999) total-tickets))
                (winner1 (unwrap! (map-get? tickets { lottery: lottery-id, number: winner1-num }) err-no-winner))
                (winner2 (unwrap! (map-get? tickets { lottery: lottery-id, number: winner2-num }) err-no-winner))
                (winner3 (unwrap! (map-get? tickets { lottery: lottery-id, number: winner3-num }) err-no-winner))
            )
            
            ;; Record winners
            (map-set winners { lottery: lottery-id, position: u1 } 
                { user: winner1, amount: first-prize, claimed: false })
            (map-set winners { lottery: lottery-id, position: u2 } 
                { user: winner2, amount: second-prize, claimed: false })
            (map-set winners { lottery: lottery-id, position: u3 } 
                { user: winner3, amount: third-prize, claimed: false })
            
            ;; Mark lottery as completed
            (map-set lotteries lottery-id (merge lottery { completed: true }))
            
            (ok { first: winner1, second: winner2, third: winner3 })
        )
    )
)

(define-public (claim-prize (lottery-id uint) (position uint))
    (let
        (
            (winner-info (unwrap! (map-get? winners { lottery: lottery-id, position: position }) err-not-winner))
            (user (get user winner-info))
            (amount (get amount winner-info))
            (fee (/ (* amount (var-get platform-fee)) u100))
            (net-amount (- amount fee))
        )
        (asserts! (is-eq tx-sender user) err-not-winner)
        (asserts! (not (get claimed winner-info)) err-already-claimed)
        
        ;; Transfer prize
        (try! (as-contract (stx-transfer? net-amount tx-sender user)))
        
        ;; Transfer fee to owner
        (and (> fee u0)
            (try! (as-contract (stx-transfer? fee tx-sender contract-owner))))
        
        ;; Mark as claimed
        (map-set winners { lottery: lottery-id, position: position }
            (merge winner-info { claimed: true })
        )
        
        (ok net-amount)
    )
)

;; Admin Functions
(define-public (set-ticket-price (price uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set ticket-price price)
        (ok price)
    )
)

(define-public (set-fee (fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= fee u10) err-invalid-amount)
        (var-set platform-fee fee)
        (ok fee)
    )
)

(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set paused true)
        (ok true)
    )
)

(define-public (resume-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set paused false)
        (ok true)
    )
)

(define-public (update-block (new-block uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set current-block new-block)
        (ok new-block)
    )
)