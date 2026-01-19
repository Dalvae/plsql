-- Bloque PL/SQL para generar usuario y clave de empleados
-- PRY2206 semana 2 - actividad sumativa
-- uso cursor for loop porq es mas facil q andar calculando los ids a mano
-- y si el profe tiene mas o menos empleados igual funciona
-- tambien use exception por si algo falla hacer rollback automatico

SET SERVEROUTPUT ON

-- variable bind para la fecha de proceso (requerimiento)
VARIABLE v_fecha_proceso VARCHAR2(10);
EXEC :v_fecha_proceso := TO_CHAR(SYSDATE, 'DD/MM/YYYY');

DECLARE
    -- variables con %TYPE para datos del empleado
    v_id_emp          EMPLEADO.id_emp%TYPE;
    v_numrun          EMPLEADO.numrun_emp%TYPE;
    v_dvrun           EMPLEADO.dvrun_emp%TYPE;
    v_pnombre         EMPLEADO.pnombre_emp%TYPE;
    v_snombre         EMPLEADO.snombre_emp%TYPE;
    v_appaterno       EMPLEADO.appaterno_emp%TYPE;
    v_apmaterno       EMPLEADO.apmaterno_emp%TYPE;
    v_fecha_nac       EMPLEADO.fecha_nac%TYPE;
    v_fecha_contrato  EMPLEADO.fecha_contrato%TYPE;
    v_sueldo_base     EMPLEADO.sueldo_base%TYPE;
    v_id_estado_civil EMPLEADO.id_estado_civil%TYPE;

    v_nombre_estado   ESTADO_CIVIL.nombre_estado_civil%TYPE;

    -- variables de trabajo
    v_nombre_completo VARCHAR2(60);
    v_nombre_usuario  VARCHAR2(20);
    v_clave_usuario   VARCHAR2(25);
    v_annos_trabajo   NUMBER;
    v_letras_apellido VARCHAR2(2);

    -- para validacion
    v_contador        NUMBER := 0;
    v_total_emp       NUMBER;
    v_fecha_proceso   DATE;

BEGIN
    DBMS_OUTPUT.PUT_LINE('Inicio proceso - fecha: ' || :v_fecha_proceso);

    -- SENTENCIA PL/SQL: convierto la fecha bind a tipo DATE usando TO_DATE
    v_fecha_proceso := TO_DATE(:v_fecha_proceso, 'DD/MM/YYYY');

    -- SENTENCIA SQL (dinamico): trunco la tabla para poder ejecutar varias veces
    -- uso EXECUTE IMMEDIATE porque TRUNCATE es DDL y no se puede usar directo en PL/SQL
    EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';

    -- SENTENCIA SQL: cuento cuantos empleados hay para despues validar con el contador
    SELECT COUNT(*) INTO v_total_emp FROM EMPLEADO;
    DBMS_OUTPUT.PUT_LINE('Empleados a procesar: ' || v_total_emp);

    -- cursor for loop para recorrer todos los empleados, asi no tengo q poner los id fijos
    FOR emp IN (SELECT id_emp, numrun_emp, dvrun_emp, pnombre_emp, snombre_emp,
                       appaterno_emp, apmaterno_emp, fecha_nac, fecha_contrato,
                       sueldo_base, id_estado_civil
                FROM EMPLEADO ORDER BY id_emp) LOOP

        v_id_emp := emp.id_emp;
        v_numrun := emp.numrun_emp;
        v_dvrun := emp.dvrun_emp;
        v_pnombre := emp.pnombre_emp;
        v_snombre := emp.snombre_emp;
        v_appaterno := emp.appaterno_emp;
        v_apmaterno := emp.apmaterno_emp;
        v_fecha_nac := emp.fecha_nac;
        v_fecha_contrato := emp.fecha_contrato;
        v_sueldo_base := emp.sueldo_base;
        v_id_estado_civil := emp.id_estado_civil;

        -- busco el nombre del estado civil
        SELECT nombre_estado_civil
        INTO   v_nombre_estado
        FROM   ESTADO_CIVIL
        WHERE  id_estado_civil = v_id_estado_civil;

        -- armo el nombre completo (con o sin segundo nombre)
        IF v_snombre IS NOT NULL THEN
            v_nombre_completo := UPPER(v_pnombre || ' ' || v_snombre || ' ' ||
                                       v_appaterno || ' ' || v_apmaterno);
        ELSE
            v_nombre_completo := UPPER(v_pnombre || ' ' || v_appaterno || ' ' ||
                                       v_apmaterno);
        END IF;

        -- calculo años trabajando
        v_annos_trabajo := TRUNC(MONTHS_BETWEEN(v_fecha_proceso, v_fecha_contrato) / 12);

        -- NOMBRE DE USUARIO:
        -- letra estado civil + 3 letras nombre + largo nombre + * + ultimo digito sueldo + dv + años
        v_nombre_usuario := LOWER(SUBSTR(v_nombre_estado, 1, 1)) ||
                           SUBSTR(v_pnombre, 1, 3) ||
                           LENGTH(v_pnombre) ||
                           '*' ||
                           MOD(v_sueldo_base, 10) ||
                           v_dvrun ||
                           v_annos_trabajo;

        -- si tiene menos de 10 años agrego X
        IF v_annos_trabajo < 10 THEN
            v_nombre_usuario := v_nombre_usuario || 'X';
        END IF;

        -- CLAVE DE USUARIO:
        -- SENTENCIA PL/SQL: estructura IF-ELSIF para determinar las letras del apellido
        -- segun el estado civil del empleado (regla de negocio)
        IF v_id_estado_civil IN (10, 60) THEN
            -- casado o union civil: primeras 2 letras
            v_letras_apellido := LOWER(SUBSTR(v_appaterno, 1, 2));
        ELSIF v_id_estado_civil IN (20, 30) THEN
            -- divorciado o soltero: primera y ultima
            v_letras_apellido := LOWER(SUBSTR(v_appaterno, 1, 1) || SUBSTR(v_appaterno, -1, 1));
        ELSIF v_id_estado_civil = 40 THEN
            -- viudo: antepenultima y penultima
            v_letras_apellido := LOWER(SUBSTR(v_appaterno, -3, 2));
        ELSIF v_id_estado_civil = 50 THEN
            -- separado: ultimas 2
            v_letras_apellido := LOWER(SUBSTR(v_appaterno, -2, 2));
        END IF;

        -- armo la clave completa
        v_clave_usuario := SUBSTR(TO_CHAR(v_numrun), 3, 1) ||
                          TO_CHAR(EXTRACT(YEAR FROM v_fecha_nac) + 2) ||
                          LPAD(MOD(v_sueldo_base - 1, 1000), 3, '0') ||
                          v_letras_apellido ||
                          v_id_emp ||
                          TO_CHAR(v_fecha_proceso, 'MMYYYY');

        -- inserto en la tabla
        INSERT INTO USUARIO_CLAVE (id_emp, numrun_emp, dvrun_emp,
                                   nombre_empleado, nombre_usuario, clave_usuario)
        VALUES (v_id_emp, v_numrun, v_dvrun,
                v_nombre_completo, v_nombre_usuario, v_clave_usuario);

        v_contador := v_contador + 1;
    END LOOP;

    -- valido que se procesaron todos comparando contador con total
    DBMS_OUTPUT.PUT_LINE('Procesados: ' || v_contador || ' de ' || v_total_emp);

    -- solo hago commit si se procesaron todos los empleados
    IF v_contador = v_total_emp THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Commit realizado ok');
    ELSE
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error - rollback');
    END IF;

EXCEPTION
    -- por si algo falla en el proceso, hago rollback pa no dejar datos a medias
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/
