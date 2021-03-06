# PRE_NETWORK_BEETLES.R
#
#
# Compute the beetle dispersion network.
# 
# This file is used to produce simulations in the paper: 
# Spread of Dutch Elm Disease in an urban forest
# Nicolas Bajeux, Julien Arino, Stephanie Portet and Richard Westwood
# Ecological Modelling


######################################################################
### SELECTION OF NEIGHBOURHOOD AND VALUES OF R_B
### replace spaces by "_" in the neighbourhood name
name_nbhd = "NORTH_RIVER_HEIGHTS"
seq_R_B = seq(from = 20, to = 380, by=20) #list of values of R_B
######################################################################

library(sqldf)
library(igraph)
library(Matrix)
library(R.utils)
library(parallel)

##############################################

### DISTANCE
#
# gives the distance between two trees
distance = function(xi,yi,xj,yj){
  d = sqrt((xi-xj)^2+(yi-yj)^2)
  return(d)
}

###NEIGHBOURS
#
#return the list of neighbours for each tree and the list of distances (for one value of R_B)
#note 1: that we first restrict the list through a square around the tree and then remove the trees too far, this allows to loop over a smaller number of trees
#note 2: the list of neighbours gives the real ID (from Tree.ID in the dataset)
neighbours = function(R_B,elms){
  distance_neighbours = list() #necessary ?
  neighbours_square = list()
  neighbours_circle = list()
  neighbours.X = list()
  neighbours.Y = list()
  for (i in 1:dim(elms)[1]){
    tree_ID = elms$Tree.ID[i]
    x0 = elms$X[i]
    y0 = elms$Y[i]
    list.inside.X = which(abs(x0-elms$X)<=R_B)
    list.inside.Y = which(abs(y0-elms$Y)<=R_B)
    list.inside.square = intersect(list.inside.X,list.inside.Y)
    #list.inside.square is the set of trees that are inside the square of center (x0,y0) and side 2R_B
    
    neighbours_square[[i]] = setdiff(elms$Tree.ID[list.inside.square],tree_ID) #gives the IDs of trees that are inside the square, except the tree itself
    list.inside.square = list.inside.square[! list.inside.square %in% i] #again, this is just to remove the value i from the vector
    
    neighbours.X[[i]] = elms$X[list.inside.square]
    neighbours.Y[[i]] = elms$Y[list.inside.square]
    
    distance_neighbours[[i]] = neighbours_square[[i]] #just to initialize at the same length
    ll = c() #vectors of trees in the square but not in the 
    
    if(length(neighbours_square[[i]])>0){
      for (j in 1:length(neighbours_square[[i]])){ 
        distance_neighbours[[i]][j] = distance(x0,y0,neighbours.X[[i]][j],neighbours.Y[[i]][j])
        if(!is.na(distance_neighbours[[i]][j])){
          if(distance_neighbours[[i]][j]>R_B){
            ll = c(ll,j)
          }
        }
      }
    }
    if(length(ll)>0){
      distance_neighbours[[i]]=distance_neighbours[[i]][-ll] #remove the neighbours too far (in the list of distances)
      neighbours_square[[i]] = neighbours_square[[i]][-ll] #remove the neighbours too far (in the list of neighbours)
    }
  }
  
  neighbours_circle = neighbours_square #After the removal, the neighbours_square is now a neighbours_circle
  
  return(list(neighbours_circ=neighbours_circle,distance_neighbours=distance_neighbours))
}

###NEIGHB_POS
#
#return the list of neighbours in the neighbourhood (not the entire city)
neighb_pos = function(elms, neighbours_circle){#position of neighbours (return a list of vectors)
  lookup_ID = elms$Tree.ID
  lookup_ID = cbind(lookup_ID,1:length(lookup_ID))#trees are positioned from 1 to N, N be the number of trees in the neighbourhood
  colnames(lookup_ID) = c("TreeID","idx")
  
  nb_pos = list()
  for (i in 1:length(neighbours_circle)) {#loop to give the position of each tree in the neighbourhood
    if (length(neighbours_circle[[i]])>0) {
      nb_pos[[i]] = neighbours_circle[[i]]*0 #initialize the vector to 0
      for (j in 1:length(neighbours_circle[[i]])) {
        pos = which(lookup_ID[,"TreeID"]==neighbours_circle[[i]][j])
        nb_pos[[i]][j] = lookup_ID[pos,"idx"]
      }
    }
    else {
      nb_pos[[i]] = mat.or.vec(1,0) #put the zero value (same as an empty list)
    }
  }
  return(nb_pos)
}

###############################################################################

# SELECT A DATE
date_TI_file = "2020-08-26"

# Set directories
source(sprintf("%s/CODE/set_directories.R", here::here()))

# Set save directory to include date of data file
DIRS$nbhd_and_date = sprintf("%s%s", DIRS$prefix_data_date, date_TI_file)
# Set directory for saving in this script
DIRS$preproc_dists = sprintf("%s/%s", DIRS$nbhd_and_date, DIRS$suffix_preproc_dists)

# Read file
elms = readRDS(sprintf("%s/elms_%s.Rds", DIRS$nbhd_and_date, name_nbhd))

list.R_B = list()
for (i in 1:length(seq_R_B)){
  list.R_B[[i]] = seq_R_B[i]
}

RUN_PARALLEL = FALSE
if (RUN_PARALLEL) {
  no_cores <- detectCores()
  # Initiate cluster
  tictoc::tic()
  cl <- makeCluster(no_cores)
  clusterExport(cl,
                c("elms"
                  ,"distance"
                  ,"neighbours"
                  ,"neighb_pos"
                ),
                envir = .GlobalEnv)
  # Run computation
  outputs = parLapply(cl = cl, X = list.R_B, fun = function(x) neighbours(x, elms))
  # Stop cluster
  stopCluster(cl)
  timeLoading=tictoc::toc()
} else {
  outputs = lapply(X = list.R_B, FUN = function(x) neighbours(x, elms))
}

for (i in 1:length(outputs)) {
  output = outputs[[i]]
  R_B = seq_R_B[i]
  print(sprintf("R_B = %s",R_B))
  neighbours_circle = output[[1]]
  distance_neighbours = output[[2]]
  neighbours_pos = neighb_pos(elms,output[[1]])
  Nb_trees = length(neighbours_circle)
  # Save results files
  saveRDS(neighbours_circle,sprintf("%s/neighbours_%strees_RB%s_%s.Rds",
                                    DIRS$preproc_dists, Nb_trees, R_B, name_nbhd))
  saveRDS(distance_neighbours,sprintf("%s/distance_neighbours_%strees_RB%s_%s.Rds",
                                      DIRS$preproc_dists, Nb_trees, R_B, name_nbhd))
  saveRDS(neighbours_pos,sprintf("%s/neighbours_pos_%strees_RB%s_%s.Rds",
                                 DIRS$preproc_dists, Nb_trees, R_B, name_nbhd))
}
