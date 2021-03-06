#' @importFrom Matrix Matrix Diagonal sparseMatrix
MLdfm <- function(Y, m, p, tol = 0.01, verbose = FALSE, orthogonal_shocks = FALSE) {
  Y <- as.matrix(Y)
  r <- nrow(Y)
  k <- ncol(Y)
  itc <- colMeans(Y, na.rm = TRUE)
  Ytmp <- na.omit(Y)
  sA <- m * (p + 1) # number of factors and size of A matrix

  Ytmp <- base::scale(Ytmp) # scale before taking principle components
  scl <- attr(Ytmp, "scaled:scale")
  # loadings on principle components and initial guess for H
  PC <- PrinComp(Y, m)
  H <- PC$loadings

  if (sum(sign(H[, 1])) < 0) {
    H[, 1] <- -H[, 1]
  }
  H <- H * (matrix(1, 1, m) %x% scl) # scale H up

  # Arbitrary initial guess for A
  A <- Matrix(0, sA, sA)
  A[1:m, 1:m] <- .1 * Diagonal(m)
  A[(m + 1):sA, 1:(m * p)] <- Diagonal(m * p)

  # Arbirary initial guess for Q
  Q <- Matrix(0, sA, sA)
  Q[1:m, 1:m] <- Diagonal(m)

  # Arbitrary intitial guess for R
  R <- diag(1, k, k)

  count <- 0
  Lik0 <- -1e10
  Conv <- 100
  while (Conv > tol | count < 5) {
    Est <- KestExact(A, Q, H, R, Y, itc, m, p)
    A <- Est$A
    Q <- Est$Q
    H <- Est$H
    R <- Est$R
    itc <- Est$itc
    Lik1 <- Est$Lik
    if(verbose) print(paste("Likelihood:", Est$Lik))
    Conv <- 200 * (Lik1 - Lik0) / abs(Lik1 + Lik0)
    Lik0 <- Lik1
    count <- count + 1
  }

  # Final Estimates
  # if (m * p == 1) {
  #   A <- sparseMatrix(i = 1, j = 1, x = c(A[1, 1]), dims = c(1, 1), symmetric = FALSE, triangular = FALSE, giveCsparse = TRUE)
  #   Q <- sparseMatrix(i = 1, j = 1, x = c(Q[1, 1]), dims = c(1, 1), symmetric = FALSE, triangular = FALSE, giveCsparse = TRUE)
  # }
  # else {
  #   A <- A[1:(m * p), 1:(m * p)]
  #   Q <- Q[1:(m * p), 1:(m * p)]
  # }
  # Ydm <- Y - matrix(1, r, 1) %x% t(itc)
  # HJ <- sparseMatrix(i = rep(1:k, m), j = (1:m) %x% rep(1, k), x = c(H), dims = c(k, m * p), symmetric = FALSE, triangular = FALSE, giveCsparse = TRUE)
  #
  # Smth <- Ksmoother(A, Q, HJ, R, Ydm)

  B  <- matrix(A[1:m, 1:(m * p)], m, m*p)
  q  <- as.matrix(Q[1:m,1:m])

  if(orthogonal_shocks){ #if we want to return a model with orthogonal shocks, rotate the parameters
    id <- Identify(H,q)
    H  <- H%*%id[[1]]
    B  <- id[[2]]%*%B%*%(diag(1,p,p)%x%id[[1]])
    q  <- id[[2]]%*%q%*%t(id[[2]])
  }

  Jb <- Matrix::Diagonal(m * p)
  Ydm <- Y - matrix(1, r, 1) %x% t(itc)

  Smth <- DSmooth(B, Jb =  Jb, q, H, R, Y = Ydm, freq = rep(1, k), LD = rep(0, k))

  #Format output a bit
  rownames(H) <- colnames(Y)
  R <- diag(R)
  names(R) <- colnames(Y)

  return(list(
    values = Smth$Ys + matrix(1, r, 1) %x% t(itc),
    Lik = Smth$Lik,
    factors = Smth$Z[, 1:m],
    unsmoothed_factors = Est$Zz[, 1:m],
    predicted_factors  = Est$Zp[, 1:m],
    B = B,
    Q = Q,
    H = H,
    R = R,
    A = A,
    itc = itc,
    Kstore = Smth$Kstr,
    PEstore = Smth$PEstr
  ))
}
