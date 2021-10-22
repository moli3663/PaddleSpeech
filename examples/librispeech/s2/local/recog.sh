#!/bin/bash

set -e

expdir=exp
datadir=data
nj=32

decode_config=conf/decode/decode.yaml
lang_model=rnnlm.model.best
lmexpdir=exp/train_rnnlm_pytorch_lm_transformer_cosine_batchsize32_lr1e-4_layer16_unigram5000_ngpu4/

lmtag='nolm'

recog_set="test-clean test-other dev-clean dev-other"
recog_set="test-clean"

# bpemode (unigram or bpe)
nbpe=5000
bpemode=unigram
bpeprefix="data/bpe_${bpemode}_${nbpe}"
bpemodel=${bpeprefix}.model

if [ $# != 3 ];then
    echo "usage: ${0} config_path dict_path ckpt_path_prefix"
    exit -1
fi

ngpu=$(echo $CUDA_VISIBLE_DEVICES | awk -F "," '{print NF}')
echo "using $ngpu gpus..."

config_path=$1
dict=$2
ckpt_prefix=$3

ckpt_dir=$(dirname `dirname ${ckpt_prefix}`)
echo "ckpt dir: ${ckpt_dir}"

ckpt_tag=$(basename ${ckpt_prefix})
echo "ckpt tag: ${ckpt_tag}"

chunk_mode=false
if [[ ${config_path} =~ ^.*chunk_.*yaml$ ]];then
    chunk_mode=true
fi
echo "chunk mode: ${chunk_mode}"
echo "decode conf: ${decode_config}"

# download language model
#bash local/download_lm_en.sh
#if [ $? -ne 0 ]; then
#    exit 1
#fi


pids=() # initialize pids

for dmethd in join_ctc; do
(
    echo "${dmethd} decoding"
    for rtask in ${recog_set}; do
    (
        echo "${rtask} dataset"
        decode_dir=${ckpt_dir}/decode/decode_${rtask/-/_}_${dmethd}_$(basename ${config_path%.*})_${lmtag}_${ckpt_tag}
        feat_recog_dir=${datadir}
        mkdir -p ${decode_dir}
        mkdir -p ${feat_recog_dir}

        # split data
        split_json.sh manifest.${rtask} ${nj}

        #### use CPU for decoding
        ngpu=0

        # set batchsize 0 to disable batch decoding
        ${decode_cmd} JOB=1:${nj} ${decode_dir}/log/decode.JOB.log \
            python3 -u ${BIN_DIR}/recog.py \
                --api v2 \
                --config ${decode_config} \
                --ngpu ${ngpu} \
                --batchsize 0 \
                --checkpoint_path ${ckpt_prefix} \
                --dict-path ${dict} \
                --recog-json ${feat_recog_dir}/split${nj}/JOB/manifest.${rtask} \
                --result-label ${decode_dir}/data.JOB.json \
                --model-conf ${config_path} \
                --model ${ckpt_prefix}.pdparams

                #--rnnlm ${lmexpdir}/${lang_model} \

        score_sclite.sh --bpe ${nbpe} --bpemodel ${bpemodel} --wer false ${decode_dir} ${dict}

    ) &
    pids+=($!) # store background pids
    i=0; for pid in "${pids[@]}"; do wait ${pid} || ((++i)); done
    [ ${i} -gt 0 ] && echo "$0: ${i} background jobs are failed." || true
    done
)
done

echo "Finished"

exit 0
