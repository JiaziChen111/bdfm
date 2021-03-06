#' @importFrom Matrix Diagonal
PCdfm <- function(Y, m, p, Bp = NULL, lam_B = 0, Hp = NULL, lam_H = 0,
                  nu_q = 0, nu_r = NULL, ID = "pc_long", reps = 1000, 
                  burn = 500, orthogonal_shocks = FALSE) {

  # ----------- Preliminaries -----------------
  Y <- as.matrix(Y)
  k <- ncol(Y)
  r <- nrow(Y)
  n_obs <- sum(is.finite(Y))
  # if (ITC) {
  #   itc <- colMeans(Y, na.rm = T)
  #   Y <- Y - matrix(1, r, 1) %x% t(itc) # De-mean data. Data is not automatically stadardized --- that is left up to the user and should be done before estimation if desired.
  # } else {
  #   itc <- rep(0, k)
  # }

  # Estimate principal components

  
  if (is.numeric(ID)) {
    if(length(ID)<m){
      stop("Number of factors is too great for selected identification routine. Try fewer factors or 'pc_full'")
    }
    PC <- PrinComp(Y[, ID, drop = FALSE], m)
    X  <- PC$components
  } else if (ID == "pc_wide") {
    PC <- PrinComp(Y, m)
    X  <- PC$components
    if (!any(!is.na(PC$components))) {
      stop("Every period contains missing data. Try setting ID to 'pc_sub'.")
    }
  } else if (ID == "pc_long") {
    long <- apply(Y,2,function(e) sum(is.finite(e)))
    long <- long>=median(long)
    if(sum(long)<m){
      stop("Number of factors is too great for selected identification routine. Try fewer factors or 'pc_full'")
    }
    PC <- PrinComp(Y[,long, drop = FALSE], m)
    X <- PC$components
  }else{
    warning(paste(ID, "not a valid identification string or index vector, defaulting to pc_long"))
    ID <- "pc_long"
    long <- apply(Y,2,function(e) sum(is.finite(e)))
    long <- long>=median(long)
    if(sum(long)<m){
      stop("Number of factors is too great for selected identification routine. Try fewer factors or 'pc_full'")
    }
    PC <- PrinComp(Y[,long, drop = FALSE], m)
    X <- PC$components
  }

  # Format Priors
  # enter priors multiplicatively so that 0 is a weak prior and 1 is a strong prior (additive        priors are relative to the number of observations)
  lam_B <- r * lam_B + 1
  nu_q <- r * nu_q + 1
  lam_H <- r * lam_H + 1
  if (is.null(nu_r)) {
    nu_r <- rep(1, k)
  } else {
    if (length(nu_r) != k) {
      stop("Length of nu_r must equal the number of observed series")
    }
    nu_r <- r * nu_r + rep(1, k)
  }
  if (is.null(Hp)) {
    Hp <- matrix(0, k, m)
  }
  if (is.null(Bp)) {
    Bp <- matrix(0, m, m * p)
  }

  # Estimate parameters of the observation equation
  Hest <- BReg_diag(X, Y, Int = F, Bp = Hp, lam = lam_H, nu = nu_r, reps = reps, burn = burn)
  H <- Hest$B
  R <- diag(c(Hest$q), k, k)

  # Estimate parameters of the transition equation (Bayesian VAR)
  Z <- stack_obs(X, p = p)
  Z <- as.matrix(Z[-nrow(Z), ])
  xx <- as.matrix(X[-(1:p), ])
  indZ <- which(apply(Z, MARGIN = 1, FUN = AnyNA))
  indX <- which(apply(xx, MARGIN = 1, FUN = AnyNA))
  ind <- unique(c(indZ, indX)) # index of rows with missing values in Z and xx
  Best <- BReg(Z[-ind, , drop = FALSE], xx[-ind, , drop = FALSE], Int = FALSE, Bp = Bp, lam = lam_B, nu = nu_q, reps = reps, burn = burn)
  B <- Best$B
  q <- Best$q

  Jb <- Matrix::Diagonal(m * p)
  
  if(orthogonal_shocks){ #if we want to return a model with orthogonal shocks, rotate the parameters
    id <- Identify(H,q)
    H  <- H%*%id[[1]]
    B  <- id[[2]]%*%B%*%(diag(1,p,p)%x%id[[1]])
    q  <- id[[2]]%*%q%*%t(id[[2]])
  }

  Est <- DSmooth(
    B = B, Jb = Jb, q = q, H = H, R = R,
    Y = Y, freq = rep(1, k), LD = rep(0, k)
  )
  
  #Format output a bit
  rownames(H) <- colnames(Y)
  R <- diag(R)
  names(R) <- colnames(Y)

  BIC <- log(n_obs) * (m * p + m^2 + k * m + k) - 2 * Est$Lik

  Out <- list(
    B = B,
    q = q,
    H = H,
    R = R,
    values = Est$Ys,
    factors = Est$Z[, 1:m],
    unsmoothed_factors = Est$Zz[, 1:m],
    predicted_factors  = Est$Zp[, 1:m],
    Qstore = Best$Qstore, # lets us look at full distribution
    Bstore = Best$Bstore,
    Rstore = Hest$Rstore,
    Hstore = Hest$Hstore,
    Kstore = Est$Kstr,
    PEstore = Est$PEstr,
    Lik = Est$Lik,
    BIC = BIC
  )
  return(Out)
}
