
## OpenMS output has 10 required format
## however, still need preprocessing

#' @export

OpenMStoMSstatsFormat <- function(input,
                                  annotation=NULL,
                                  useUniquePeptide=TRUE,
                                  fewMeasurements="remove",
                                  removeProtein_with1Feature=FALSE,
                                  summaryforMultipleRows=max){
    
    if (is.null(fewMeasurements)) {
        stop('** Please select \'remove\' or \'keep\' for \'fewMeasurements\'.')
    }
    
    if (!is.element(fewMeasurements, c('remove', 'keep'))) {
        stop('** Please select \'remove\' or \'keep\' for \'fewMeasurements\'.')
    }
    
    if (is.null(annotation)) {
        if (sum(is.na(input$Condition)) > 0){
            stop('** All or partial annotation is missing. Please prepare \'annotation\' as one of input.')
        }
    } else {
        annotinfo <- annotation
    }

    ## Check correct option or input
    requiredinput.general <- c("ProteinName", "PeptideSequence", "PrecursorCharge", 
                               "FragmentIon", "ProductCharge", "IsotopeLabelType",
                               "Condition", "BioReplicate", "Run", "Intensity")
    
    ################################
    ## 1. check general input and use only required columns.
    ################################
    
    if (!all(requiredinput.general %in% colnames(input))) {
        
        misssing.col <- requiredinput.general[!requiredinput.general %in% colnames(input)]
        
        stop(paste0("** Please check the required input. The required input needs : ", 
                   toString(missing.col)))
    } else {
        input <- input[, colnames(input) %in% requiredinput.general]
    }
    
    ## get annotation
    if (is.null(annotation)) {
        annotinfo <- unique(input[, c("Run", "Condition", 'BioReplicate')])	
    } else {
        
        ## check annotation
        required.annotation <- c('Condition', 'BioReplicate', 'Run')
        
        if (!all(required.annotation %in% colnames(annotation))) {
            
            missedAnnotation <- which(!(required.annotation %in% colnames(annotation)))
            
            stop(paste("**", toString(required.annotation[missedAnnotation]), 
                       "is not provided in Annotation. Please check the annotation file."))
        } else {
            annotinfo <- annotation
        }
    }
    
    ##############################
    ## 2. remove featuares with all na or zero
    ## some rows have all zero values across all MS runs. They should be removed.
    ##############################
  
    input$fea <- paste(input$PeptideSequence,
                       input$PrecursorCharge,
                       input$FragmentIon,
                       input$ProductCharge,
                       sep="_")
  
    inputtmp <- input[!is.na(input$Intensity) & input$Intensity > 1, ]
    
    count <- inputtmp %>% group_by(fea) %>% summarise(length=length(Intensity))
    
    ## get feature with all NA or zeros
    getfea <- count[count$length > 0, 'fea']
    
    if (nrow(getfea) > 0) {
        
        nfea.remove <- length(unique(input$fea)) - nrow(getfea)
        input <- input[which(input$fea %in% getfea$fea), ]

        message(paste0('** ', nfea.remove, ' features have all NAs or zero intensity values and are removed.'))
    } else {
        stop(message('No intensity is available. Please check the input.'))
    }
    
    rm(inputtmp)
    
    ################################################
    ## 3. remove peptides which are used in more than one protein
    ## we assume to use unique peptide
    ################################################
    if (useUniquePeptide) {
    
        pepcount <- unique(input[, c("ProteinName", "PeptideSequence")]) ## Protein.group.IDs or Sequence
        pepcount$PeptideSequence <- factor(pepcount$PeptideSequence)
    
        ## count how many proteins are assigned for each peptide
        structure <- pepcount %>% group_by(PeptideSequence) %>% summarise(length=length(ProteinName))
        
        remove_peptide <- structure[structure$length != 1, ]
    
        ## remove the peptides which are used in more than one protein
        if (nrow(remove_peptide) != 0) {
            input <- input[-which(input$PeptideSequence %in% remove_peptide$PeptideSequence), ]
      
            message('** Peptides, that are used in more than one proteins, are removed.')
        } else {
            message('** All peptides are unique peptides in proteins.')
        }
    
        rm(structure)
        rm(remove_peptide)
    }
  
    ##############################
    ##  4. remove features which has 1 or 2 measurements across runs
    ##############################
    if (fewMeasurements == "remove") {
    
        ## it is the same across experiments. # measurement per feature. 
        xtmp <- input[!is.na(input$Intensity) & input$Intensity > 0, ]
        count_measure <- xtabs( ~fea, xtmp)
    
        remove_feature_name <- count_measure[count_measure < 3]
    
        if (length(remove_feature_name) > 0) {
            
            input <- input[-which(input$fea %in% names(remove_feature_name)), ]
            
            message(paste0('** ', length(remove_feature_name), 
                           ' features have 1 or 2 intensities across runs and are removed.'))
            
        }
    }
  
    ##############################
    ## 5. remove proteins with only one peptide and charge per protein
    ##############################
  
    if (removeProtein_with1Feature) {
        
        ## remove protein which has only one peptide
        tmp <- unique(input[, c("ProteinName", 'fea')])
        tmp$ProteinName <- factor(tmp$ProteinName)
        count <- xtabs( ~ ProteinName, data=tmp)
        lengthtotalprotein <- length(count)
    
        removepro <- names(count[count <= 1])
    
        if (length(removepro) > 0) {
      
            input <- input[-which(input$ProteinName %in% removepro), ]
            
            message(paste0("** ", length(removepro), 
                           ' proteins, which have only one feature in a protein, are removed among ', 
                           lengthtotalprotein, ' proteins.'))
        } else {
            message("** All proteins have at least two features.")
        }
    }

    ##############################
    ## 6. remove multiple measurements per feature and run
    ##############################
  
    count <- aggregate(Intensity ~ fea, data=input, FUN=length)
  
    ## if any feature has more number of total MS runs, 
    if (any(unique(count$Intensity) > length(unique(input$Run)))) {
    
        ## maximum or sum up abundances among intensities for identical features within one run
        input_w <- dcast( ProteinName + PeptideSequence + PrecursorCharge + FragmentIon ~ Run, data=input, 
                          value.var='Intensity', 
                          fun.aggregate=summaryforMultipleRows, fill='NA') 
    
        ## reformat for long format
        input <- melt(input_w, id=c('ProteinName', 'PeptideSequence', 'PrecursorCharge', 'FragmentIon'))
        colnames(input)[which(colnames(input) %in% c('variable','value'))] <- c("Run","Intensity")
    
        message('** Multiple measurements in a feature and a run are summarized by summaryforMultipleRows.')
    
    } else {
        
        ## still need to fill incomplete rows
        input_w <- dcast( ProteinName + PeptideSequence + PrecursorCharge + FragmentIon + ProductCharge ~ Run, data=input, 
                          value.var='Intensity', 
                          fill='NA') 
        
        ## reformat for long format
        input <- melt(input_w, 
                      id=c('ProteinName', 'PeptideSequence', 'PrecursorCharge', 'FragmentIon', 'ProductCharge'))
        colnames(input)[which(colnames(input) %in% c('variable','value'))] <- c("Run","Intensity")
        
        message('** No multiple measurements in a feature and a run.')
    }
    
    ##############################
    ## 10. class of intensity is character, change it as numeric
    ##############################
    
    input$Intensity <- as.numeric(input$Intensity)
    
    ##############################
    ## 11. merge annotation
    ##############################
    input <- merge(input, annotinfo, by='Run', all=TRUE)
    
    ## fill in extra columns
    input.final <- data.frame("ProteinName" = input$ProteinName,
                              "PeptideSequence" = input$PeptideSequence,
                              "PrecursorCharge" = input$PrecursorCharge,
                              "FragmentIon" = input$FragmentIon,
                              "ProductCharge" = input$ProductCharge,
                              "IsotopeLabelType" = "L",
                              "Condition" = input$Condition,
                              "BioReplicate" = input$BioReplicate,
                              "Run" = input$Run,
                              "Intensity" = input$Intensity)
    
    input <- input.final
    input$ProteinName <- factor(input$ProteinName)
    
    rm(input.final)
  
	return(input)
}


