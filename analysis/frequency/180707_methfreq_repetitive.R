#!/usr/bin/Rscript
library(tidyverse)
library(GenomicRanges)
library(ggridges)
library(GGally)
source("../../plot/methylation_plot_utils.R")

# set this to TRUE to remove unnecessary objects throughout the process
limitedmem=TRUE

# set directories
root="/dilithium/Data/Nanopore/projects/nomeseq/analysis"
plotdir=file.path(root,"plots/repeats")
if (!dir.exists(plotdir)) dir.create(plotdir,recursive=TRUE)
datroot=file.path(root,"pooled/methylation/mfreq_all")
regdir=file.path(root,"database/hg38")
# get file paths of data
cells=c("MCF10A","MCF7","MDAMB231")
fpaths=tibble(cell=cells,
          cpg=file.path(datroot,paste0(cell,".cpg.methfreq.txt.gz")),
          gpc=file.path(datroot,paste0(cell,".gpc.methfreq.txt.gz")))
pd=gather(fpaths,key=calltype,value=filepath,-cell)

# validation group (illumina)
if (F) {
    illpd=tibble(cell="GM12878_illumina",calltype=c("cpg","gpc"),
                 filepath=file.path("/dilithium/Data/Nanopore/projects/nomeseq/analysis/validation/scNOMe/methfreq",
                                    paste("GM12878_sample",calltype,"methfreq.txt.gz",sep=".")))
    pd=bind_rows(pd,illpd)
}

# regions
if (T){
    regnames=c("DNA","RTP","LINE","SINE")
    reg.info=tibble(regtype=regnames)%>%
        mutate(filepath=paste0(regdir,"/hg38_repeats_",regtype,".bed"))
    subset=FALSE
}
#read in regions
cat("reading in the region\n")
extracols="regtype"
db=lapply(reg.info$filepath,function(x){
    load_db(x,extracols)})
covthr=2
trinuc="GCG"

MethByRegion <- function(pd,reg){
    cat(paste0(reg,"\n"))
    dat.list=lapply(seq(dim(pd)[1]),function(i){
        pd.samp=pd[i,]
        cat(paste0(pd.samp$cell,":",pd.samp$calltype,"\n"))
        # read in the data
        dat=tabix_mfreq(pd.samp$filepath,dbpath=reg,
                        cov=covthr,trinuc_exclude=trinuc)
        # overlaps
        cat("getting methylation by region\n")
        db=load_db(reg,extracols)
        dat.ovl=getRegionMeth(dat,db)
        rm(dat);gc()
        #get labels
        cat("attaching labels\n")
        dat.ovl$feature.type=db$regtype[dat.ovl$feature.index]
        dat.ovl$samp=pd.samp$cell
        dat.ovl$calltype=pd.samp$calltype
        dat.ovl
    })
    dat.cat=do.call(rbind,dat.list)
}

dat.list=lapply(reg.info$filepath,function(x){
    MethByRegion(pd,x)})

dat.all=do.call(rbind,dat.list)

dat.spread = dat.all %>%
    select(-totcov,-numsites)%>%
    spread(key=samp,value=freq)%>% na.omit()

dat.cpg=dat.all[which(dat.all$calltype=="cpg"),]
dat.gpc=dat.all[which(dat.all$calltype=="gpc"),]

# boxplot
cat("plotting\n")
cpg.box=ggplot(dat.cpg,aes(x=feature.type,
                         y=freq,color=samp))+
    geom_boxplot(alpha=0.5)+
    theme_bw()
gpc.box=ggplot(dat.gpc,aes(x=feature.type,
                         y=freq,color=samp))+
    geom_boxplot(alpha=0.5)+
    theme_bw()
makeridge <- function(data){
    ggplot(data,aes(x=freq,y=factor(feature.type),fill=samp,color=samp))+
        geom_density_ridges(alpha=0.1)+xlim(c(0,1))+
        labs(title=data$calltype[1],
             x="Methylation frequency",
             y="Repeat type")+
        theme_bw()
}
cpg.ridge=makeridge(dat.cpg)
gpc.ridge=makeridge(dat.gpc)

if ( F ){
    plotpath=file.path(plotdir,"repeats_boxplot_by_feature.pdf")
    pdf(plotpath,width=9,height=5,useDingbats=F)
    print(cpg.box)
    print(gpc.box)
    dev.off()
}

if ( F ){
    plotpath=file.path(plotdir,"repeats_ridges_by_feature.pdf")
    pdf(plotpath,width=9,height=5,useDingbats=F)
    print(cpg.ridge)
    print(gpc.ridge)
    dev.off()
}

# how many in each type?
x = group_by(dat.cpg,feature.type) %>%
    summarize(n())

makescatter <- function(data,plottype="duo"){
    x = data %>% ungroup() %>%
        select(-c("totcov","numsites","feature.type","calltype"))%>%
        spread(samp,freq) %>% select(-"feature.index")%>%
        na.omit()
    if (plottype == "duo") {
        g=ggduo(x,title=paste(data$calltype[1],data$feature.type[1],sep=" : "))
    } else if (plottype == "pair") {
        g=ggpairs(x,title=paste(data$calltype[1],data$feature.type[1],sep=" : "))
    }
    print(g)
}

if (F) {
    plotn=1000
    plotpath=file.path(plotdir,"bcan_repeates_scatterplot_pair.pdf")
    pdf(plotpath,width=10,height=10,useDingbats=F)
    # scatter plot
    for (ftype in unique(dat.cpg$feature.type)){
        cat(paste0("plotting ",ftype,"\n"))
        cpg.sub=dat.cpg[which(dat.cpg$feature.type==ftype),]
        gpc.sub=dat.gpc[which(dat.gpc$feature.type==ftype),]
        # unique features that occur in all samples
        fnum=bind_rows(cpg.sub,gpc.sub)%>%
            group_by(feature.index)%>%
            summarize(num=n())%>%
            filter(num==dim(pd)[1])
        if (dim(fnum)[1]>plotn){
            cat("too many number of points, subsampling \n")
            subsample=sample(fnum$feature.index,plotn)
        } else {
            subsample=fnum$feature.index
        }
        cpg.sub=cpg.sub[cpg.sub$feature.index %in% subsample,]
        gpc.sub=gpc.sub[gpc.sub$feature.index %in% subsample,]
        
        # plot
        cat("cpg\n")
        makescatter(cpg.sub,"pair")
        cat("gpc\n")
        makescatter(gpc.sub,"pair")
    }
    dev.off()
}

# just plot LINE elements
if (F) {
    plotpre=file.path(plotdir,"bcan_LINE")
    dat.sub = dat.all[which(dat.all$feature.type=="LINE"),]
    # densities
    g = ggplot(dat.sub,aes(x=freq,group=samp))+
        facet_grid(calltype~.,scales="free") +
        xlim(c(0,1))+ggtitle("LINE")+theme_bw()
    g.density = g +
        geom_density(aes(y=..scaled..,color=samp,fill=samp,alpha=0.1))
    g.freqpoly = g +
        geom_freqpoly(aes(color=samp,alpha=0.1))
    g.hist = g +
        geom_histogram(aes(color=samp,fill=samp,alpha=0.1))
    g.ecdf = g +
        stat_ecdf(aes(color=samp,alpha=0.1))
    
    plotpath = paste0(plotpre,"_densities.pdf")
    pdf(plotpath,useDingbats=F)
    for (p in list(g.density,g.freqpoly,g.hist,g.ecdf)){
        print(p)
    }
    dev.off()
    # 2D density pairwise
    dat.spread = dat.sub%>%select(-totcov,-numsites)%>%
        spread(samp,freq)%>%na.omit()
    combos = as.tibble(t(combn(unique(dat.sub$samp),2)))
    names(combos)=c("one","two")
    plotpath = paste0(plotpre,"_pairwise.pdf")
    pdf(plotpath,useDingbats=F)
    for (i in seq(dim(combos)[1])){
        print(i)
        one=combos$one[i]
        two=combos$two[i]
        for ( mod in c("cpg","gpc")){
            dat.plt = dat.spread[which(dat.spread$calltype==mod),]%>%
                select(feature.index,calltype,one=one,two=two)
            n = 75
            breaks=seq(0,1,length.out=n)
            dat.plt$one = cut(dat.plt$one,breaks)
            dat.plt$two = cut(dat.plt$two,breaks)
            levels(dat.plt$one)=levels(dat.plt$two)=breaks[1:length(breaks)-1]
            hist = dat.plt%>%group_by(one,two)%>%
                summarize(count=n())%>%ungroup()%>%
                mutate(one=as.numeric(as.character(one)),
                       two=as.numeric(as.character(two)))
            cutoff=round(quantile(hist$count,0.9))
            hist = hist%>%mutate(count=ifelse(count>cutoff,cutoff,count))
            g = ggplot(hist,aes(x=one,y=two))+
                geom_tile(aes(fill=count))+
#                geom_hex(aes(fill=log(..count..)),bins=100)+
                scale_fill_distiller(palette="Spectral")+
                theme_bw()+lims(x=c(0,1),y=c(0,1))+
                labs(title=mod,x=one,y=two)
            print(g)
        }
        
    }
    dev.off()
}
# selecting out some specific regions
if (T) {
    db.sub = db[[which(reg.info$regtype=="LINE")]]
    dat.sub = dat.all[which(dat.all$feature.type=="LINE"),]%>%
        filter(totcov>50,numsites>20)
    dat.spread = dat.sub%>%select(-totcov,-numsites)%>%
        spread(samp,freq)%>%na.omit()
    combos = as.tibble(t(combn(unique(dat.sub$samp),2)))
    names(combos)=c("one","two")
    dat.sig=tibble()
    for (i in seq(dim(combos)[1])){
        print(i)
        sampone=combos$one[i]
        samptwo=combos$two[i]
        del.cpg = dat.spread[which(dat.spread$calltype=="cpg"),] %>%
            select(feature.index,calltype,one=sampone,two=samptwo) %>%
            mutate(del=abs(one-two))%>%filter(del>0.5)%>%
            mutate(sampone=sampone,samptwo=samptwo)
        del.gpc = dat.spread[which(dat.spread$calltype=="gpc"),] %>%
            select(feature.index,calltype,one=sampone,two=samptwo) %>%
            mutate(del=abs(one-two))%>%filter(del>0.1)%>%
            mutate(sampone=sampone,samptwo=samptwo)
        del = del.cpg%>% select(feature.index,sampone,samptwo,cpg=del)
        del$gpc = del.gpc$del[match(del$feature.index,del.gpc$feature.index)]
        del = del%>%na.omit()
        dat.sig = dat.sig%>%bind_rows(del)
    }
    dat.sig = dat.sig %>% arrange(desc(gpc),desc(cpg))
    db.tb = as.tibble(db.sub)
    db.sig = db.sub[dat.sig$feature.index]
    out = db.tb[dat.sig$feature.index,]%>%
        bind_cols(dat.sig)%>%
        select(seqnames,start,end,id,score,strand,sampone,samptwo,cpg,gpc)
    outpath=file.path(plotdir,"LINE_regions.bed")
    if (F) write_tsv(out,outpath,col_names=F)
}
# plot these regions
if (T){
    win=1000
    pltwin.gr = resize(db.sig,width=width(db.sig)+win,fix="center")
    for (i in seq_along(pltwin.gr)){
        pltreg = pltwin.gr[i]
    }
    
}
