#!/usr/bin/Rscript
library(tidyverse)
library(GenomicRanges)
library(GGally)
library(getopt)
srcdir=dirname(get_Rscript_filename())
if (is.na(srcdir)){ srcdir="." }
source(file.path(srcdir,"../../script/methylation_plot_utils.R"))
library(parallel)
cores=detectCores() - 2
# root
root=commandArgs(trailingOnly=TRUE)[1]
if (is.na(root)){
    root="/dilithium/Data/Nanopore/projects/nomeseq/analysis" # default
}

# data
datroot=file.path(root,"pooled/methylation/mfreq")
cells=c("MCF10A","MCF7","MDAMB231")
fpaths=tibble(cell=cells,
              cpg=file.path(datroot,paste0(cell,".cpg.methfreq.txt.gz")),
              gpc=file.path(datroot,paste0(cell,".gpc.methfreq.txt.gz")))
pd=gather(fpaths,key=calltype,value=filepath,-cell)
plotdir=file.path(root,"plots/bcan_expression")
annodir=file.path(root,"annotations/breastcancer")

# get the db
if (FALSE){
    dbpaths = system(paste0("readlink -f ",
                            annodir,
                            "/*by_expression*TSS.bed"),
                     intern=T)
    extracols=c("gene","one","two","direction")
    db.list = lapply(dbpaths,load_db,extracols)
    db.gr = do.call(c,db.list)
    plotpath = file.path(plotdir,"breastcancer_diff_expression_regions_2kb.pdf")
}
if (TRUE){
    dbpath = file.path(annodir,"bcan_diffexp_bothcancer_cgi.TSS.bed")
    extracols="name"
    db.gr = load_db(dbpath,extracols)
    plotpath = file.path(plotdir,"breastcancer_diff_expression_bothcancer_regions_average_10kb.pdf")
}

db.gr = db.gr[order(db.gr$score,decreasing=T)]
reg.gr = promoters(db.gr,upstream=5000,downstream=5000)

plotter <- function(data,reg,tss,calltype){
    g=ggplot(data,aes(x=start,y=freq,color=cell,group=cell))+
        geom_point(size=0.5,alpha=0.5)+
        geom_rug(inherit.aes=F,mapping=aes(x=start))+
        geom_vline(xintercept=start(tss),linetype=2)+
        lims(y=c(0,1),x=c(start(reg),end(reg)))+
        labs(x=paste0("Coordinate on ",seqnames(reg)),
             y="Methylation Frequency",
             title=paste(calltype,reg$id,"(",strand(tss),")",reg$score))+
        theme_bw()+
        theme(panel.grid.major = element_blank(),
              panel.grid.minor = element_blank(),
              axis.text = element_text(color="black"),
              legend.position="bottom")
    g
}    


pdf(plotpath,width=4,height=3,useDingbats=F)
for (i in seq_along(db.gr)){
    print(i)
    db.sub = db.gr[i]
    reg.sub = reg.gr[i]
    dat.list=lapply(seq(dim(pd)[1]),function(i){
        tabix_mfreq(pd$filepath[i],reg.sub) %>%
            mutate(calltype=pd$calltype[i],
                   cell=pd$cell[i])
    })
    dat.sub = do.call(rbind,dat.list)

    dat.cpg = dat.sub[which(dat.sub$calltype=="cpg"),]
    dat.gpc = dat.sub[which(dat.sub$calltype=="gpc"),]
#    rm.cpg = calculate_rollmean(dat.cpg) %>% na.omit() %>%
#        mutate(calltype="cpg")
#    rm.gpc = calculate_rollmean(dat.gpc) %>% na.omit() %>%
#        mutate(calltype="gpc")
#    dat.rm = do.call(rbind,list(rm.cpg,rm.gpc))
    g.cpg = plotter(dat.cpg,reg.sub,db.sub,"cpg") +
        geom_smooth(se=F,method="loess",span=0.2)
    g.gpc = plotter(dat.gpc,reg.sub,db.sub,"gpc") +
        geom_smooth(se=F,method="loess",span=0.1)
    print(g.cpg)
    print(g.gpc)
}
dev.off()
