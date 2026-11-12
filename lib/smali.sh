#!/usr/bin/env bash
# ============================================================================
# apkx — Smali / Dex / Jar / Java Conversion & Smart Jadx Decompilation
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

# Smart converter: .dex -> smali, .java -> smali
cmd_to_smali() {
    local target="${1:-${APK_FILE:-}}"
    [ -z "$target" ] && fail "Usage: apkx smali <file.dex | File.java>"
    if [[ "$target" == *.dex ]]; then
        cmd_dex2smali "$target"
    else
        cmd_java2smali "$target"
    fi
}

cmd_dex2smali() {
    local target="${1:-${APK_FILE:-}}"
    [ -z "$target" ] || [ ! -f "$target" ] && fail "Target DEX file not found: ${target:-<none>}"
    local base_name="${target%.*}"
    info "Converting DEX (${target}) -> ${base_name}/smali ..."
    $BAKSMALI_CMD d "$target" -l -o "$base_name/smali"
    ok "Converted to ${base_name}/smali"
}

cmd_jar2dex() {
    local target="${1:-${APK_FILE:-}}"
    [ -z "$target" ] || [ ! -f "$target" ] && fail "Target JAR file not found: ${target:-<none>}"
    local base_name="${target%.*}"
    info "Converting JAR (${target}) -> ${base_name}.dex ..."
    if [ -x "$D8" ] || command -v "$D8" &>/dev/null; then
        "$D8" --output . "$target"
        [ -f "classes.dex" ] && [ "$base_name" != "classes" ] && mv "classes.dex" "${base_name}.dex"
    else
        $DX_CMD --dex --output="${base_name}.dex" "$target"
    fi
    ok "Converted to ${base_name}.dex"
}

cmd_java2smali() {
    local target="${1:-${APK_FILE:-}}"
    target="${target%.java}"
    [ -z "$target" ] || [ ! -f "${target}.java" ] && fail "Java file not found: ${target}.java"
    info "Compiling ${target}.java -> class -> dex -> smali ..."
    javac "${target}.java" && "$D8" "${target}.class" && $BAKSMALI_CMD d classes.dex
    rm -f "${target}.class" classes.dex
    ok "Converted ${target}.java to smali"
}

cmd_smali2java() {
    local target="${1:-${APK_FILE:-}}"
    info "Decompiling smali (${target}) -> Java ..."
    cmd_jadx_smali "$target" "-ds" "out/"
}

# Decompile a single .smali file (with its imported smali dependencies & mapping.jobf) or open APK/DEX/JAR in jadx-gui
# Usage:
#   apkx jadx <file.smali>            -> open in jadx-gui
#   apkx jadx <file.smali> vim        -> decompile to /tmp/apkx/jadx/ and open in gvim (or mvim/vim)
#   apkx jadx <file.smali> <editor>   -> decompile to /tmp/apkx/jadx/ and open with <editor> (e.g. code, subl, cat)
cmd_jadx_smali() {
    local smali_file="${1:-${APK_FILE:-}}"
    local open_cmd="${2:-}"
    [ -z "$smali_file" ] || [ ! -f "$smali_file" ] && fail "Target file not found: ${smali_file:-<none>}"

    if [[ "$smali_file" != *.smali ]]; then
        info "Opening ${smali_file} in jadx-gui..."
        "${JADX_CMD}-gui" --show-bad-code --escape-unicode "$smali_file" &
        return 0
    fi

    local smali_name base_class_name
    smali_name=$(basename "$smali_file" ".smali")
    base_class_name="${smali_name%%\$*}"

    local resources_file="smali/build/apk/resources.arsc"
    local mapping_file="mapping.jobf"
    local deobf_args=""

    if [ ! -e "$resources_file" ]; then
        resources_file=""
    fi
    if [ -e "$mapping_file" ]; then
        deobf_args="--deobf --deobf-min 1 --deobf-cfg-file $mapping_file"
    fi

    # Extract referenced classes across smali/smali* directories so jadx resolves types & deobfuscation
    local imported_smali
    imported_smali=$(grep -Eo 'L(\w|\$|/)+;' "$smali_file" 2>/dev/null | cut -c2- | tr -d ';' | sort -ur | while IFS= read -r cls; do
        for sdir in smali/smali smali/smali_classes2 smali/smali_classes3 smali/smali_classes4; do
            if [ -f "${sdir}/${cls}.smali" ] && [ "${sdir}/${cls}.smali" != "$smali_file" ]; then
                echo "${sdir}/${cls}.smali"
                break
            fi
        done
    done | xargs || true)

    if [ -n "$open_cmd" ]; then
        # Map "vim" shorthand to GUI gvim (fallback to mvim -> vim)
        case "$open_cmd" in
            vim|--vim|-v)
                if command -v gvim &>/dev/null; then
                    open_cmd="gvim"
                elif command -v mvim &>/dev/null; then
                    open_cmd="mvim"
                else
                    open_cmd="vim"
                fi
                ;;
        esac

        local jadx_out_dir="/tmp/apkx/jadx"
        rm -rf "$jadx_out_dir" 2>/dev/null || true
        mkdir -p "$jadx_out_dir"
        info "Decompiling ${smali_name}.smali -> ${CYAN}${jadx_out_dir}${NC} ..."

        # shellcheck disable=SC2086
        "$JADX_CMD" --show-bad-code --comments-level debug --escape-unicode $deobf_args \
            -d "$jadx_out_dir" "$smali_file" $imported_smali $resources_file >/dev/null 2>&1 || true

        local deobf_name=""
        if [ -f "$mapping_file" ]; then
            deobf_name=$(grep -Eo "^ *c *${base_class_name} *= *.*" "$mapping_file" 2>/dev/null | awk -F= '{print $2}' | xargs || true)
        fi
        deobf_name="${deobf_name:-$base_class_name}"

        local out_java
        out_java=$(find "${jadx_out_dir}/sources" -name "${deobf_name}.java" 2>/dev/null | head -n 1 || true)
        if [ -z "$out_java" ]; then
            out_java=$(find "${jadx_out_dir}/sources" -name "*.java" 2>/dev/null | head -n 1 || true)
        fi

        if [ -z "$out_java" ] || [ ! -f "$out_java" ]; then
            fail "Jadx failed to produce a .java file in ${jadx_out_dir}/sources"
        fi

        ok "Generated Java: ${GREEN}${out_java}${NC}"
        info "Opening with ${CYAN}${open_cmd}${NC}..."
        if [[ "$open_cmd" == *vim ]]; then
            "$open_cmd" -c "set autoread | edit!" "$out_java"
        else
            "$open_cmd" "$out_java"
        fi
    else
        # Clear jadx-gui project cache for this smali class (jadx hashes only method/field signatures,
        # so body-only smali edits would otherwise hit stale cached Java code in jadx-gui!)
        local jadx_cache_projects
        for jadx_cache_projects in \
            "$HOME/Library/Caches/io.github.skylot.jadx/projects" \
            "${XDG_CACHE_HOME:-$HOME/.cache}/io.github.skylot.jadx/projects"; do
            if [ -d "$jadx_cache_projects" ]; then
                rm -rf "${jadx_cache_projects}/${smali_name}-"* "${jadx_cache_projects}/${base_class_name}-"* 2>/dev/null || true
            fi
        done

        # shellcheck disable=SC2086
        "${JADX_CMD}-gui" --show-bad-code --escape-unicode $deobf_args \
            -sc "$smali_name" "$smali_file" $imported_smali $resources_file
        ok "Jadx decompilation complete"
    fi
}
cmd_jd_gui() {
    local target="${1:-${APK_FILE:-}}"
    if [ -z "${JD_GUI_JAR:-}" ] || [ ! -f "$JD_GUI_JAR" ]; then
        fail "jd-gui JAR not found in ${APKX_BIN_DIR}"
    fi
    info "Launching JD-GUI ($(basename "$JD_GUI_JAR"))..."
    if [ -n "$target" ]; then
        java -jar "$JD_GUI_JAR" "$target" &
    else
        java -jar "$JD_GUI_JAR" &
    fi
}

smali2jar_dir() {
    local from_smali="$1"
    local to_jar="$2"
    local dex_name
    dex_name=$(basename "$from_smali")

    info "Converting ${from_smali} -> ${to_jar} ..."
    mkdir -p "build/smali2jar" "$(dirname "$to_jar")"
    rm -rf "build/smali2jar/$dex_name"
    cp -R "$from_smali" "build/smali2jar/$dex_name"

    # Strip synthetic / bridge / varargs modifiers so Java code can call across boundaries
    info "Preprocessing synthetic/bridge modifiers in ${dex_name}..."
    find "build/smali2jar/$dex_name" -name '*.smali' -print0 | \
        xargs -0 -P 8 -n 500 perl -pi -e 's/ bridge synthetic / /g; s/ synthetic / /g; s/ varargs / /g'

    info "Assembling ${dex_name}.dex ..."
    $SMALI_CMD a "build/smali2jar/$dex_name" -o "build/${dex_name}.dex"

    info "Converting ${dex_name}.dex -> JAR ..."
    "$D2J_DEX2JAR" "build/${dex_name}.dex" --force -o "build/${dex_name}.jar"

    local proguard_rules="$PLUGIN_DIR/$PLUGIN_MODULE/proguard-rules.pro"
    local mapping_file=""
    if [ -e "$proguard_rules" ]; then
        mapping_file=$(grep -Eo '\-applymapping +".*"' "$proguard_rules" 2>/dev/null | grep -Eo '".*"' | tr -d '"' || true)
        [ -n "$mapping_file" ] && mapping_file="$PLUGIN_DIR/$PLUGIN_MODULE/$mapping_file"
    fi

    if [ -n "$mapping_file" ] && [ -e "$mapping_file" ]; then
        info "Deobfuscating with mapping: ${mapping_file} ..."
        $RECONSTRUCT_CMD --agree -jar "build/${dex_name}.jar" -mapping "$mapping_file" -output "$to_jar" >/dev/null
    else
        mv "build/${dex_name}.jar" "$to_jar"
    fi

    rm -rf "build/smali2jar/$dex_name"
    ok "Generated ${to_jar}"
}

# Remove unused device-specific/TPU/HAL bloat from smali/assets and sync apktool.yml doNotCompress
prune_unused_assets() {
    local smali_root="$1"
    local assets_dir="${smali_root}/assets"
    local yml_file="${smali_root}/apktool.yml"
    [ ! -d "$assets_dir" ] && return 0

    info "Pruning unused model/firmware assets in ${CYAN}${assets_dir}${NC} ..."

    # Normalize all_in_*_assets_* folder names to all_in_assets_* if present
    local d
    for d in "$assets_dir"/all_in_*_assets_processed_manifest; do
        if [ -d "$d" ] && [ ! -d "$assets_dir/all_in_assets_processed_manifest" ]; then
            mv "$d" "$assets_dir/all_in_assets_processed_manifest"
        fi
    done
    for d in "$assets_dir"/all_in_*_assets_symbols; do
        if [ -d "$d" ] && [ ! -d "$assets_dir/all_in_assets_symbols" ]; then
            mv "$d" "$assets_dir/all_in_assets_symbols"
        fi
    done

    local removed_count=0
    local item base_name
    for item in "$assets_dir"/*; do
        [ -e "$item" ] || continue
        base_name=$(basename "$item")
        case "$base_name" in
            # Universal pattern blacklist for Pixel Tensor TPU (P21..P39+), HAL APEX firmware & unused models
            *.apex.br|*.apex.json|release-keys_*|\
            *-[pP][2-9][0-9]*|*_[pP][2-9][0-9]*|*[tT][pP][uU]*|*[cC]ustom_[oO]p*|*[cC]ustom-[oO]p*|*darwinn*|\
            [pP][2-9][0-9]|kepler*|awb|research|_kotlin|\
            serengeti_*|ceftazidime_*|eclipse_*|edamame_*|almond-*|pecan-*|walnut-*|chess-*|\
            gyrfalcon*|lancet*|avenh*|deblur_*|deeprestore_*|decepticon_*|fusion_pwc_*|hawk_*|\
            hoi_classifier*|hssd_*|pssd_*|fssd_*|looknet_*|matting_v*|midasnet_*|mobile_raid_*|\
            mosaic_*|motion-*|motion.*|movenet_*|night_sight_*|panoptic_segmenter*|people_depth_ordering*|\
            portrait_matting_mask*|raid_*|saliency*|shadow_segmenter*|siamese_*|cyclops_*|mnv4_*|\
            tcn_scoring*|foreground_color_estimator*|geo_cal*|centaur_*|GS[0-9]*_*|\
            libhalide_hexagon*)
                rm -rf "$item"
                removed_count=$(( removed_count + 1 ))
                ;;
            # Random 16-char alphanumeric PairIP decoy assets (e.g. 2dCjyhv2Kulkho80)
            [0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z][0-9a-zA-Z])
                rm -rf "$item"
                removed_count=$(( removed_count + 1 ))
                ;;
        esac
    done

    # Sync apktool.yml: remove any `- assets/...` entry under doNotCompress whose file no longer exists
    if [ -f "$yml_file" ]; then
        SMALI_ROOT_ENV="$smali_root" perl -ni -e '
            if (/^\s*-\s+(assets\/\S+)\s*$/) {
                my $rel = $1;
                next unless -e "$ENV{SMALI_ROOT_ENV}/$rel";
            }
            print;
        ' "$yml_file"
    fi

    local remaining_size
    remaining_size=$(du -sh "$assets_dir" 2>/dev/null | awk '{print $1}' || echo "?")
    ok "Pruned ${removed_count} unused asset entries (remaining assets size: ${GREEN}${remaining_size}${NC})"
}

# Keep only source/app/src/main/java/defpackage inside a jadx output directory
prune_jadx_source_dir() {
    local src_root="$1"
    [ ! -d "$src_root" ] && return 0

    local defpkg_dir="${src_root}/app/src/main/java/defpackage"
    if [ ! -d "$defpkg_dir" ]; then
        return 0
    fi

    info "Pruning ${CYAN}${src_root}${NC} to keep only ${GREEN}app/src/main/java/defpackage${NC} ..."
    local tmp_defpkg="${src_root}_defpackage_tmp_$$"
    mv "$defpkg_dir" "$tmp_defpkg"
    rm -rf "$src_root"
    mkdir -p "${src_root}/app/src/main/java"
    mv "$tmp_defpkg" "$defpkg_dir"
    ok "Kept only ${defpkg_dir}"
}

# Merge/move a smali package directory from $1 into $2 and remove $1
move_smali_dir() {
    local src="$1"
    local dst="$2"
    [ ! -d "$src" ] && return 1

    local count
    count=$(find "$src" -name "*.smali" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        rm -rf "$src"
        return 1
    fi

    mkdir -p "$(dirname "$dst")"
    if [ ! -d "$dst" ]; then
        mv "$src" "$dst"
    else
        cp -a "$src/." "$dst/"
        rm -rf "$src"
    fi
    # Clean up empty parent directory if any
    rmdir "$(dirname "$src")" 2>/dev/null || true
    echo "$count"
    return 0
}

# Organize smali package directories across smali/, smali_classes2/, and smali_classes3/
# 1. Move non-obfuscated packages (android, androidx, com, java, kotlin, kotlinx, org, wireless)
#    from smali/ -> smali_classes2/ (keeps main classes.dex under 64K limit).
# 2. Move shared library packages needed for deobfuscation & plugin compilation
#    (android, androidx/wear if present, com/google, com/bumptech, j$) -> smali_classes3/.
cmd_adjust_smali() {
    local target_dir="${1:-${APK_FILE:-}}"
    local smali_root=""

    if [ -n "$target_dir" ] && [ -d "$target_dir/smali/smali" ]; then
        smali_root="$target_dir/smali"
    elif [ -n "$target_dir" ] && [ -d "$target_dir/smali" ]; then
        smali_root="$target_dir"
    elif [ -d "smali/smali" ]; then
        smali_root="smali"
    elif [ -d "smali" ] && [ -f "apktool.yml" ]; then
        smali_root="."
    else
        fail "Could not find decoded smali directory (expected ./smali/smali or <dir>/smali)"
    fi

    info "Organizing smali directories in ${CYAN}${smali_root}${NC} ..."
    mkdir -p "${smali_root}/smali_classes2" "${smali_root}/smali_classes3"

    local moved_total=0
    local count=""
    local pkg src_dir

    # Step 1: Merge smali_classes4..9 into smali_classes3 and remove smali_classes4..9
    for src_dir in "${smali_root}"/smali_classes[4-9]; do
        [ -d "$src_dir" ] || continue
        local rel_src="${src_dir#${smali_root}/}"
        cp -a "$src_dir/." "${smali_root}/smali_classes3/"
        rm -rf "$src_dir"
        info "Merged ${CYAN}${rel_src}${NC} -> ${GREEN}smali_classes3${NC} and removed ${rel_src}"
    done

    # Step 2: Move package folders from smali/ & smali_classes3/ -> smali_classes2/
    local to_classes2=("android" "androidx" "com" "java" "kotlin" "kotlinx" "org" "wireless")
    for src_dir in "${smali_root}/smali" "${smali_root}/smali_classes3"; do
        [ -d "$src_dir" ] || continue
        local rel_src="${src_dir#${smali_root}/}"
        for pkg in "${to_classes2[@]}"; do
            if count=$(move_smali_dir "${src_dir}/${pkg}" "${smali_root}/smali_classes2/${pkg}"); then
                info "Moved ${CYAN}${rel_src}/${pkg}${NC} -> ${GREEN}smali_classes2/${pkg}${NC} (${count} files)"
                moved_total=$(( moved_total + count ))
            fi
        done
    done

    # Step 3: Move android, androidx/wear (if present), com/google, com/bumptech, j$ -> smali_classes3/
    local to_classes3=("android" "androidx/wear" "com/google" "com/bumptech" "j$")
    for src_dir in "${smali_root}/smali" "${smali_root}/smali_classes2"; do
        [ -d "$src_dir" ] || continue
        local rel_src="${src_dir#${smali_root}/}"
        for pkg in "${to_classes3[@]}"; do
            if count=$(move_smali_dir "${src_dir}/${pkg}" "${smali_root}/smali_classes3/${pkg}"); then
                info "Moved ${CYAN}${rel_src}/${pkg}${NC} -> ${GREEN}smali_classes3/${pkg}${NC} (${count} files)"
                moved_total=$(( moved_total + count ))
            fi
        done
    done

    # Step 4: Gather all root *.smali into smali/, then move [a-i]*.smali -> smali_classes3/
    for src_dir in "${smali_root}/smali_classes2" "${smali_root}/smali_classes3"; do
        [ -d "$src_dir" ] || continue
        local root_cnt
        root_cnt=$(find "$src_dir" -maxdepth 1 -name "*.smali" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$root_cnt" -gt 0 ]; then
            find "$src_dir" -maxdepth 1 -name "*.smali" -print0 | \
                xargs -0 -n 500 sh -c 'target="$1"; shift; [ $# -gt 0 ] && mv "$@" "$target/"' _ "${smali_root}/smali"
        fi
    done

    local total_root_smali
    total_root_smali=$(find "${smali_root}/smali" -maxdepth 1 -name "*.smali" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$total_root_smali" -gt 18000 ]; then
        # GCam 11+ (>18,000 root files, ~149K methods > 2x64K limit):
        # Split cleanly by alphabet: [a-f]* -> smali_classes3, [g-j]* -> smali_classes4, [k-z]* -> smali
        local af_count gj_count
        af_count=$(find "${smali_root}/smali" -maxdepth 1 -name "[a-f]*.smali" 2>/dev/null | wc -l | tr -d ' ')
        gj_count=$(find "${smali_root}/smali" -maxdepth 1 -name "[g-j]*.smali" 2>/dev/null | wc -l | tr -d ' ')
        mkdir -p "${smali_root}/smali_classes4"
        find "${smali_root}/smali" -maxdepth 1 -name "[a-f]*.smali" -print0 | \
            xargs -0 -n 500 sh -c 'target="$1"; shift; [ $# -gt 0 ] && mv "$@" "$target/"' _ "${smali_root}/smali_classes3"
        find "${smali_root}/smali" -maxdepth 1 -name "[g-j]*.smali" -print0 | \
            xargs -0 -n 500 sh -c 'target="$1"; shift; [ $# -gt 0 ] && mv "$@" "$target/"' _ "${smali_root}/smali_classes4"
        info "Moved ${CYAN}smali/[a-f]*.smali${NC} -> ${GREEN}smali_classes3/${NC} (${af_count} files)"
        info "Moved ${CYAN}smali/[g-j]*.smali${NC} -> ${GREEN}smali_classes4/${NC} (${gj_count} files; smali keeps [k-z]*.smali)"
        moved_total=$(( moved_total + af_count + gj_count ))
    elif [ "$total_root_smali" -gt 9500 ]; then
        # GCam 9.x / 10.x (<=18,000 root files, fits in 2 DEXs): [a-h]* -> smali_classes3, [i-z]* -> smali
        local ah_count
        ah_count=$(find "${smali_root}/smali" -maxdepth 1 -name "[a-h]*.smali" 2>/dev/null | wc -l | tr -d ' ')
        find "${smali_root}/smali" -maxdepth 1 -name "[a-h]*.smali" -print0 | \
            xargs -0 -n 500 sh -c 'target="$1"; shift; [ $# -gt 0 ] && mv "$@" "$target/"' _ "${smali_root}/smali_classes3"
        info "Moved ${CYAN}smali/[a-h]*.smali${NC} -> ${GREEN}smali_classes3/${NC} (${ah_count} files; smali keeps [i-z]*.smali)"
        moved_total=$(( moved_total + ah_count ))
    fi

    # Step 5: Prune unused assets in smali/assets and sync apktool.yml doNotCompress
    prune_unused_assets "$smali_root"

    # Step 6: Prune jadx source directory if present, keeping only source/app/src/main/java/defpackage
    local proj_parent
    proj_parent=$(dirname "$smali_root")
    if [ -d "${proj_parent}/source" ]; then
        prune_jadx_source_dir "${proj_parent}/source"
    fi

    # Step 7: Ensure .gitignore exists in project directory to prevent committing >100MB .so / build artifacts
    if [ -d "$proj_parent" ] && [ ! -f "${proj_parent}/.gitignore" ]; then
        cat > "${proj_parent}/.gitignore" <<'GITIGNORE_EOF'
logs/
pkg/
**/build/
*.log
*.zip
*.apk
*.apkm
*.xapk
*.idsig
*.jobf
*.apex.br
.DS_Store
.gradle
.idea
libagc.so
libgcastartup.so
Version.smali
GITIGNORE_EOF
        info "Generated default ${CYAN}${proj_parent}/.gitignore${NC} (ignores libgcastartup.so, *.apk, build/)"
    fi

    if [ "$moved_total" -gt 0 ]; then
        ok "Smali directory layout organized (${moved_total} files moved)"
    else
        ok "Smali directory layout already organized (0 files needed moving)"
    fi

    # Step 3: Strip debug directives (.line, .source, .local, .param, .restart, .end local, .prologue)
    if [ "${2:-}" != "--no-strip" ]; then
        info "Stripping debug directives (.line, .source, .local, .param, .prologue) in ${CYAN}${smali_root}${NC} ..."
        local start_ts=$SECONDS
        local total_files
        total_files=$(find "$smali_root" -name "*.smali" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$total_files" -gt 0 ]; then
            find "$smali_root" -name "*.smali" -print0 | \
                xargs -0 -P 8 -n 500 perl -ni -e 'print unless /\.(?:line |source |local |param |restart |end local|prologue)/'
        fi
        local elapsed=$(( SECONDS - start_ts ))
        ok "Stripped debug directives from ${total_files} smali files (${elapsed}s)"
    fi
}

cmd_smali2jar() {
    local jar_output_dir="${1:-$PLUGIN_DIR/$PLUGIN_TARGET_MODULE/libs}"
    info "Packaging smali directories to JARs -> ${jar_output_dir}"

    if [ -d "smali/smali" ]; then
        smali2jar_dir "smali/smali" "$jar_output_dir/classes.jar"
    fi
    local idx
    for idx in 2 3 4 5 6 7 8 9 10; do
        # Skip the plugin injection directory itself (default: smali_classes2)
        if [ "smali_classes${idx}" = "$SMALI_INJECT_DIR" ]; then
            continue
        fi
        if [ -d "smali/smali_classes${idx}" ]; then
            smali2jar_dir "smali/smali_classes${idx}" "$jar_output_dir/classes${idx}.jar"
        fi
    done
}
