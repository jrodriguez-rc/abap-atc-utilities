"! <p class="shorttext synchronized" lang="en">Run ATC Checks</p>
CLASS zcl_atc_run_checks DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    TYPES:
      "! <p class="shorttext synchronized" lang="en">Results</p>
      BEGIN OF ts_result,
        findings            TYPE cl_satc_adt_ch_factory=>ty_atc_verdicts,
        has_caused_abortion TYPE abap_bool,
      END OF ts_result.

    "! <p class="shorttext synchronized" lang="en">CONSTRUCTOR</p>
    "!
    "! @parameter profile_name | <p class="shorttext synchronized" lang="en">Variant profile name</p>
    METHODS constructor
      IMPORTING
        profile_name TYPE csequence OPTIONAL.

    "! <p class="shorttext synchronized" lang="en">Execute checks</p>
    "!
    "! @parameter object_keys | <p class="shorttext synchronized" lang="en">Workbench Object keys</p>
    "! @parameter result | <p class="shorttext synchronized" lang="en">Checks result</p>
    "! @raising cx_adt_rest | <p class="shorttext synchronized" lang="en">ADT Exception</p>
    METHODS check
      IMPORTING
        object_keys   TYPE satc_t_r3tr_keys
      RETURNING
        VALUE(result) TYPE zcl_atc_run_checks=>ts_result
      RAISING
        cx_adt_rest.

  PROTECTED SECTION.

  PRIVATE SECTION.
    DATA:
      profile_name_of_checks TYPE satc_ci_chk_variant.

    METHODS get_default_variant
      RETURNING
        VALUE(variant) TYPE satc_ci_chk_variant.

    METHODS build_project
      IMPORTING
        object_keys        TYPE satc_t_r3tr_keys
      RETURNING
        VALUE(atc_project) TYPE REF TO if_satc_md_project.

    METHODS execute_atc_project
      IMPORTING
        atc_project         TYPE REF TO if_satc_md_project
      RETURNING
        VALUE(execution_id) TYPE satc_d_id.

    METHODS retrieve_findings
      IMPORTING
        execution_id  TYPE satc_d_id
      RETURNING
        VALUE(result) TYPE zcl_atc_run_checks=>ts_result
      RAISING
        cx_adt_rest.

    METHODS get_standard_check_ids
      EXPORTING
        check_profile TYPE satc_d_ac_chk_profile_name
        check_ids     TYPE satc_t_ids.

    METHODS generate_project_title
      IMPORTING
        object_keys   TYPE satc_t_r3tr_keys
      RETURNING
        VALUE(result) TYPE satc_d_description.

ENDCLASS.



CLASS zcl_atc_run_checks IMPLEMENTATION.


  METHOD constructor.

    IF profile_name IS NOT INITIAL.
      profile_name_of_checks = profile_name.
    ELSE.
      profile_name_of_checks = get_default_variant( ).
    ENDIF.

  ENDMETHOD.


  METHOD check.

    DATA(atc_project) = build_project( object_keys ).

    DATA(execution_id) = execute_atc_project( atc_project ).

    result = retrieve_findings( execution_id ).

  ENDMETHOD.


  METHOD get_default_variant.

    TRY.
        DATA(atc_config) = CAST if_satc_ac_config_ci( cl_satc_ac_config_factory=>get_read_access( ) ).
        atc_config->get_ci_check_variant( IMPORTING e_name = variant ).
      CATCH cx_satc_root cx_sy_move_cast_error.
        CLEAR: variant.
    ENDTRY.

    IF variant IS INITIAL.
      variant = 'DEFAULT'.
    ENDIF.

  ENDMETHOD.


  METHOD build_project.

    DATA:
      msg_text           TYPE string,
      title              TYPE satc_d_description,
      is_rslt_transient  TYPE abap_bool,
      project_parameters TYPE REF TO cl_satc_ac_project_parameters,
      key_iterator       TYPE REF TO cl_satc_ac_iterate_fixed_keys.

    CREATE OBJECT key_iterator.
    key_iterator->set_object_keys( object_keys ).

    title = generate_project_title( object_keys ).

    CREATE OBJECT project_parameters.

    project_parameters->set_project_title( title ).
    project_parameters->set_is_transient( abap_false ).
    project_parameters->set_check_profile_name( profile_name_of_checks ).
    project_parameters->set_evaluate_exemptions( abap_true ).
    project_parameters->set_evaluate_runtime_error( abap_true ).
    project_parameters->set_object_key_iterator( key_iterator ).

    atc_project = cl_satc_ac_project_builder=>create_builder( )->create_project( project_parameters ).

  ENDMETHOD.


  METHOD execute_atc_project.

    DATA success TYPE abap_bool.
    TRY.
        CALL FUNCTION 'SATC_EXECUTE_PROJECT'
          EXPORTING
            i_project = atc_project
          IMPORTING
            e_exec_id = execution_id
            e_success = success.

        IF success IS INITIAL.
          CLEAR execution_id.
        ENDIF.

      CATCH cx_satc_root.
        CLEAR execution_id.
    ENDTRY.

  ENDMETHOD.


  METHOD retrieve_findings.

    DATA(access) = cl_satc_adt_result_read_access=>create( cl_satc_adt_result_reader=>create( ) ).

    access->read_display_id_4_execution_id( EXPORTING i_execution_id = execution_id
                                            IMPORTING e_display_id   = DATA(display_id) ).

    access->read_findings( EXPORTING i_display_id = display_id
                           IMPORTING e_findings   = result-findings ).

    access->read_metrics_4_id( EXPORTING i_display_id          = display_id
                               IMPORTING e_has_caused_abortion = result-has_caused_abortion ).

  ENDMETHOD.


  METHOD get_standard_check_ids.

    DATA:
      atc_config    TYPE REF TO if_satc_ac_config_cm,
      cm_profile    TYPE crmprfid,
      check         TYPE cl_satc_checkman_queries=>ty_s_check,
      checks        TYPE cl_satc_checkman_queries=>ty_t_checks,
      check_queries TYPE REF TO cl_satc_checkman_queries.

    CLEAR: check_ids, check_profile.

    TRY.
        atc_config = cl_satc_ac_config_cm_factory=>get_access_to_atc_config( ).
        atc_config->get_standard_profile( IMPORTING  e_name = cm_profile ).
      CATCH cx_satc_root.
        cm_profile = 'STANDARD'.
    ENDTRY.
    check_profile = cm_profile.

    CREATE OBJECT check_queries.
    checks = check_queries->get_checks_of_profile( cm_profile ).

    DELETE checks WHERE
      dvlpr_scope = if_satc_ac_check_attributes=>scope-never. "#EC CI_SORTSEQ

    LOOP AT checks INTO check.
      INSERT check-atc_id INTO TABLE check_ids.
    ENDLOOP.

  ENDMETHOD.


  METHOD generate_project_title.

    IF lines( object_keys ) = 1.
      result = object_keys[ 1 ]-obj_name.
      RETURN.
    ENDIF.

    DATA(r3tr_keys) = object_keys.

    SORT r3tr_keys BY obj_name.

    LOOP AT r3tr_keys INTO DATA(r3tr_key).

      result = COND #( WHEN result IS INITIAL THEN result
                                              ELSE |{ result }, { r3tr_key-obj_name }...| ).

      IF sy-tabix > 1.
        EXIT.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.


ENDCLASS.
