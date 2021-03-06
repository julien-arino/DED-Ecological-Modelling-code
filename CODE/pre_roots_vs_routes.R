# PRE_ROOTS_VS_ROUTES.R
# roots vs roads :)
#
#
# Compute network for roots, taking into account roads and other obstacles.
# 
# This file is used to produce simulations in the paper: 
# Spread of Dutch Elm Disease in an urban forest
# Nicolas Bajeux, Julien Arino, Stephanie Portet and Richard Westwood
# Ecological Modelling
# 
# Please note: running some of this code requires a substantial amount of RAM.

library(osmdata)
library(sf)

# Set directories
source(sprintf("%s/CODE/set_directories.R", here::here()))

# LOGICAL GATES
# If you want to refresh the OSM data, set this to TRUE. Otherwise, pre-saved data is used
REFRESH_OSM_DATA = FALSE
# This code can be hard to run. Should we show progress?
VERBOSE_OUTPUT = FALSE
# Plot networks
PLOT_NETWORKS = FALSE

if (REFRESH_OSM_DATA) {
  if (VERBOSE_OUTPUT) {
    writeLines("Starting refresh of OSM data")
  }
  # Get exact bounding polygon for Winnipeg
  bb_poly = getbb(place_name = "winnipeg", format_out = "polygon")
  # Road types to download from OSM
  road_types = c("motorway","trunk","primary","secondary","tertiary","residential","unclassified")
  # List to store all different road types in
  ROADS = list()
  # Get roads of the given type
  for (rt in road_types) {
    ROADS[[rt]] <- opq(bbox = bb_poly) %>%
      add_osm_feature(key = 'highway', value = rt) %>%
      osmdata_sf () %>%
      trim_osmdata (bb_poly)
  }
  # Variable to store union of all roads
  roads = c(ROADS[["motorway"]],
            ROADS[["trunk"]],
            ROADS[["primary"]],
            ROADS[["secondary"]],
            ROADS[["tertiary"]],
            ROADS[["residential"]],
            ROADS[["unclassified"]])
  saveRDS(roads,sprintf("%s/Winnipeg_roads.Rds",DIRS$DATA))
  #same thing with the rail
  rail <- opq(bbox = bb_poly) %>%
    add_osm_feature(key = 'railway', value = "rail") %>%
    osmdata_sf () %>%
    trim_osmdata (bb_poly)
  saveRDS(rivers,sprintf("%s/Winnipeg_rail.Rds",DIRS$DATA))
  #same thing with the rivers
  rivers <- opq(bbox = bb_poly) %>%
    add_osm_feature(key = 'waterway', value = "river") %>%
    osmdata_sf () %>%
    trim_osmdata (bb_poly)
  saveRDS(rivers,sprintf("%s/Winnipeg_rivers.Rds",DIRS$DATA))
  #same thing with the parking lots
  parkings <- opq(bbox = bb_poly) %>%
    add_osm_feature(key = 'amenity', value = "parking") %>%
    osmdata_sf () %>%
    trim_osmdata (bb_poly)
  saveRDS(parkings,sprintf("%s/Winnipeg_parkings.Rds",DIRS$DATA))
  # All sources of root cuts
  all_root_cutters = c(roads, rail, rivers, parkings)
  saveRDS(all_root_cutters,sprintf("%s/Winnipeg_all_root_cutters.Rds",DIRS$DATA))
} else {
  if (VERBOSE_OUTPUT) {
    writeLines("Starting load of existing OSM data")
  }
  roads = readRDS(sprintf("%s/Winnipeg_roads.Rds",DIRS$DATA))
  rail = readRDS(sprintf("%s/Winnipeg_rail.Rds",DIRS$DATA))
  rivers = readRDS(sprintf("%s/Winnipeg_rivers.Rds",DIRS$DATA))
  parkings = readRDS(sprintf("%s/Winnipeg_parkings.Rds",DIRS$DATA))
  all_root_cutters = readRDS(sprintf("%s/Winnipeg_all_root_cutters.Rds",DIRS$DATA))
}

# There can be several versions of the tree inventory file, load the latest
TI_files = list.files(path = DIRS$DATA,
                      pattern = glob2rx("tree_inventory_elms*.Rds"))
selected_TI_file = sort(TI_files, decreasing = TRUE)[1]
# Override if needed by selecting manually one of the files in TI_files, for instance
# selected_TI_file = TI_files[1]
# Get the date, to save distance files with that information
date_TI_file = substr(selected_TI_file, 21, 30)

# Read elms csv file (could also read the RDS..)
elms <- readRDS(sprintf("%s/%s", DIRS$DATA, selected_TI_file))

if (VERBOSE_OUTPUT) {
  writeLines("Computing distances between all tree pairs")
}
# Compute distances and select the ones matching the criterion. 
# Work with X,Y (which are in metres), rather than lon,lat
elms_xy = cbind(elms$X, elms$Y)
# CAREFUL: The next call returns a large object (>10GB). Only run on a machine with enough memory.
D_dist = dist(elms_xy)
# CAREFUL AGAIN: the next call returns a >20GB object and further requires close to 80GB RAM to work.
D_mat = as.matrix(D_dist)
# Clean up and do garbage collection (force return of memory to the system)
rm(D_dist)
gc()

# Take a very conservative upper bound for root system extent: 3 times the maximum height. This
# means that if two trees of maximum height were next to one another, their respective root
# systems would reach 3 times their height..
elms_max_distance_2_trees = 6*max(elms$TreeHeight)
idx_D_mat = which(D_mat > elms_max_distance_2_trees)
# Set distance to zero if trees are too far
D_mat[idx_D_mat] = 0
# Clean up and garbage collection again (rm typically does not suffice here)
rm(idx_D_mat)
gc()
# Some more tidying
if (VERBOSE_OUTPUT) {
  writeLines("Preparing indices")
}
# Keep only pairs with nonzero distance (i.e., <= 6*elms_max_distance_2_trees).
indices = which(D_mat !=0, arr.ind = TRUE)
# Also, only keep one of the edges, not both directions.
indices = indices[which(indices[,"row"] > indices[,"col"]),]

# Make data frame
# Save the distance matrix (can save time next time)
if (VERBOSE_OUTPUT) {
  writeLines("Create DISTS dataframe")
}
# Rather than create all fields at the same time, we build the table somewhat progressively.
# This might avoid some memory issues..
DISTS = data.frame(idx_i = indices[,1])
DISTS$ID_i = elms$Tree.ID[DISTS$idx_i]
DISTS$height_i = elms$TreeHeight[DISTS$idx_i]
DISTS$x_i = elms$X[DISTS$idx_i]
DISTS$y_i = elms$Y[DISTS$idx_i]
DISTS$lat_i = as.numeric(elms$lat[DISTS$idx_i])
DISTS$lon_i = as.numeric(elms$lon[DISTS$idx_i])
DISTS$ngbhd_i = elms$Neighbourhood[DISTS$idx_i]
DISTS$idx_j = indices[,2]
DISTS$ID_j = elms$Tree.ID[DISTS$idx_j]
DISTS$height_j = elms$TreeHeight[DISTS$idx_j]
DISTS$x_j = elms$X[DISTS$idx_j]
DISTS$y_j = elms$Y[DISTS$idx_j]
DISTS$lat_j = as.numeric(elms$lat[DISTS$idx_j])
DISTS$lon_j = as.numeric(elms$lon[DISTS$idx_j])
DISTS$ngbhd_j = elms$Neighbourhood[DISTS$idx_j]
DISTS$dist = D_mat[indices]
# Clean up and garbage collect
rm(D_mat)
gc()

# The locations of the origins of the pairs
tree_locs_orig = cbind(DISTS$lon_i, DISTS$lat_i)
# The locations of the destinations of the pairs
tree_locs_dest = cbind(DISTS$lon_j, DISTS$lat_j)

if (VERBOSE_OUTPUT) {
  writeLines("Creating line segments between all sufficiently close trees")
}
tree_pairs = do.call(sf::st_sfc,
                     lapply(
                       1:nrow(tree_locs_orig),
                       function(i){
                         sf::st_linestring(
                           matrix(
                             c(tree_locs_orig[i,],
                               tree_locs_dest[i,]), 
                             ncol=2,
                             byrow=TRUE)
                         )
                       }
                     )
)

if (PLOT_NETWORKS) {
  pdf(file = sprintf("%s/elms_pairs_preproc.pdf", DIRS$RESULTS),
      width = 50, height = 50)
  plot(tree_pairs)
  dev.off()
}


# Set both crs to be the same
st_crs(tree_pairs) = st_crs(all_root_cutters$osm_lines$geometry)

# The main cut stage: compute all intersections
if (VERBOSE_OUTPUT) {
  writeLines("Computing intersections between tree pairs segments and OSM objects")
}
tree_pairs_all_root_cutters = sf::st_intersects(x = all_root_cutters$osm_lines$geometry,
                                                y = tree_pairs)

tree_pairs_all_root_cutters_intersect = c()
for (i in 1:length(tree_pairs_all_root_cutters)) {
  if (length(tree_pairs_all_root_cutters[[i]])>0) {
    tree_pairs_all_root_cutters_intersect = c(tree_pairs_all_root_cutters_intersect,
                                              tree_pairs_all_root_cutters[[i]])
  }
}
tree_pairs_all_root_cutters_intersect = sort(tree_pairs_all_root_cutters_intersect)
to_keep = 1:dim(tree_locs_orig)[1]
to_keep = setdiff(to_keep,tree_pairs_all_root_cutters_intersect)

if(PLOT_NETWORKS){
  pdf(file = sprintf("%s/elms_pairs_postproc.pdf", DIRS$RESULTS),
      width = 50, height = 50)
  plot(tree_pairs[to_keep])
  dev.off() 
}

# Finally, indicate which distance classes the tree combinations satisfy
h_tmp = mat.or.vec(nr = dim(DISTS)[1], nc =5)
for (h in 1:5) {
  s_tmp = (DISTS$height_i+DISTS$height_j)*h
  h_tmp[which(DISTS$dist <= s_tmp),h] = 1
}
colnames(h_tmp) = sprintf("h%d",1:5)
DISTS = cbind(DISTS, h_tmp)

# Keep only the edges not intersected by a road or a river
DISTS = DISTS[to_keep,]

# Final save of the results
if (VERBOSE_OUTPUT) {
  writeLines("Final save, we're almost done")
}
saveRDS(DISTS, file = sprintf("%s/elms_distances_roots_%s.Rds", DIRS$DATA, date_TI_file))
