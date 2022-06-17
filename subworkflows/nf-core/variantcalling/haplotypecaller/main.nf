include { GATK4_MERGEVCFS                             as MERGE_HAPLOTYPECALLER } from '../../../../modules/nf-core/modules/gatk4/mergevcfs/main'
include { GATK4_GENOTYPEGVCFS                         as GENOTYPEGVCFS         } from '../../../../modules/nf-core/modules/gatk4/genotypegvcfs/main'
include { GATK4_HAPLOTYPECALLER                       as HAPLOTYPECALLER       } from '../../../../modules/nf-core/modules/gatk4/haplotypecaller/main'
include { GATK_JOINT_GERMLINE_VARIANT_CALLING         as JOINT_GERMLINE        } from '../../../../subworkflows/nf-core/gatk4/joint_germline_variant_calling/main'
include { GATK_SINGLE_SAMPLE_GERMLINE_VARIANT_CALLING as SINGLE_SAMPLE         } from '../../../../subworkflows/nf-core/gatk4/single_sample_germline_variant_calling/main'

workflow RUN_HAPLOTYPECALLER {
    take:
    cram                            // channel: [mandatory] [meta, cram, crai, interval.bed]
    fasta                           // channel: [mandatory]
    fasta_fai                       // channel: [mandatory]
    dict                            // channel: [mandatory]
    dbsnp                           // channel: []
    dbsnp_tbi
    known_sites
    known_sites_tbi
    intervals_bed_combined          // channel: [optional]


    main:

    ch_versions = Channel.empty()
    filtered_vcf = Channel.empty()

    HAPLOTYPECALLER(
        cram,
        fasta,
        fasta_fai,
        dict,
        dbsnp,
        dbsnp_tbi)

    // Figure out if using intervals or no_intervals
    HAPLOTYPECALLER.out.vcf.branch{
            intervals:    it[0].num_intervals > 1
            no_intervals: it[0].num_intervals <= 1
        }.set{haplotypecaller_vcf_branch}

    HAPLOTYPECALLER.out.tbi.branch{
            intervals:    it[0].num_intervals > 1
            no_intervals: it[0].num_intervals <= 1
        }.set{haplotypecaller_tbi_branch}

    // Only when using intervals
    MERGE_HAPLOTYPECALLER(
        haplotypecaller_vcf_branch.intervals
            .map{ meta, vcf ->

                new_meta = [patient:meta.patient, sample:meta.sample, status:meta.status, gender:meta.gender, id:meta.sample, num_intervals:meta.num_intervals]

                [groupKey(new_meta, new_meta.num_intervals), vcf]
            }.groupTuple(),
        dict)

    haplotypecaller_vcf = Channel.empty().mix(
        MERGE_HAPLOTYPECALLER.out.vcf,
        haplotypecaller_vcf_branch.no_intervals)

    haplotypecaller_tbi = Channel.empty().mix(
        MERGE_HAPLOTYPECALLER.out.tbi,
        haplotypecaller_tbi_branch.no_intervals)

    if (params.joint_germline) {

        // haplotypecaller_vcf_list = haplotypecaller_vcf.toList()
        // haplotypecaller_tbi_list = haplotypecaller_vcf.toList()

        // joint_germline_vcf_tbi = [ [id: "joint_germline"],
        //                             haplotypecaller_vcf_list,
        //                             haplotypecaller_tbi_list ]
        // GATK_JOINT_GERMLINE_VARIANT_CALLING(
        //     joint_germline_vcf_tbi,
        //     fasta,
        //     fasta_fai,
        //     intervals,
        //     dict,
        //     dbsnp,
        //     dbsnp_tbi,
        //     allelespecific?
        //     resources?
        //     annotation?
        //     "BOTH",
        //     true,
        //     truthsensitivity -> parameter or module?
        // )

        // filtered_vcf = JOINT_GERMLINE.out.vcf
        // ch_versions = ch_versions.mix(GATK_JOINT_GERMLINE_VARIANT_CALLING.out.versions)
    } else {

        //Scatter/gather on WGS, on targeted data run all intervals at once to avoid  "A USER ERROR has occurred: Bad input: VCF contains no variants or no variants with INFO score key "CNN_1D"" which happens on small-ish regions frequently
        if(params.wes){
            single_sample_in = Channel.empty().mix(haplotypecaller_vcf.join(haplotypecaller_tbi).combine(intervals_bed_combined).map{
                meta, vcf, tbi, intervals ->
                [[id:meta.id, patient:meta.patient, sample:meta.sample, gender:meta.gender, status:meta.status, num_intervals:1 ],
                vcf, tbi, intervals]
            })
        }else{
            single_sample_in = Channel.empty().mix(HAPLOTYPECALLER.out.vcf.join(HAPLOTYPECALLER.out.tbi).join(cram).map{ meta, vcf, tbi, cram, crai, intervals ->
                [meta, vcf, tbi, intervals]
            })
        }

        SINGLE_SAMPLE(single_sample_in,
                        fasta,
                        fasta_fai,
                        dict,
                        known_sites,
                        known_sites_tbi)

        filtered_vcf = SINGLE_SAMPLE.out.filtered_vcf
        ch_versions = ch_versions.mix(SINGLE_SAMPLE.out.versions)
    }


    ch_versions = ch_versions.mix(MERGE_HAPLOTYPECALLER.out.versions)
    ch_versions = ch_versions.mix(HAPLOTYPECALLER.out.versions)

    emit:
    versions = ch_versions
    filtered_vcf
}
