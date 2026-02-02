-- caso 2: aporte sbif por avances y super avances
-- se calculan los aportes del año actual segun los tramos de la tabla tramo_aporte_sbif
-- los dos cursores son explicitos, uno con parametro

SET SERVEROUTPUT ON SIZE UNLIMITED


DECLARE
    v_año_actual NUMBER := EXTRACT(YEAR FROM SYSDATE);

    -- cursor 1 explicito sin parametro: obtiene los meses con avances o savances
    CURSOR c_meses IS
        SELECT DISTINCT TO_CHAR(fecha_transaccion, 'MMYYYY') AS mes_anno
        FROM transaccion_tarjeta_cliente
        WHERE EXTRACT(YEAR FROM fecha_transaccion) = v_año_actual
          AND cod_tptran_tarjeta IN (102, 103)
        ORDER BY mes_anno;

    -- cursor 2 explicito con parametro: detalle de transacciones por mes
    -- aca se usa monto_total_transaccion que es el monto con interes
    CURSOR c_transacciones(p_mes_anno VARCHAR2) IS
        SELECT c.numrun, c.dvrun, t.nro_tarjeta, tt.nro_transaccion,
               tt.fecha_transaccion, ttp.nombre_tptran_tarjeta,
               tt.monto_total_transaccion, tt.cod_tptran_tarjeta
        FROM transaccion_tarjeta_cliente tt
        JOIN tarjeta_cliente t ON tt.nro_tarjeta = t.nro_tarjeta
        JOIN cliente c ON t.numrun = c.numrun
        JOIN tipo_transaccion_tarjeta ttp ON tt.cod_tptran_tarjeta = ttp.cod_tptran_tarjeta
        WHERE TO_CHAR(tt.fecha_transaccion, 'MMYYYY') = p_mes_anno
          AND tt.cod_tptran_tarjeta IN (102, 103)
        ORDER BY tt.fecha_transaccion, c.numrun;

    v_porc_aporte  NUMBER;
    v_aporte       NUMBER;

    -- para acumular el resumen mensual por tipo
    v_monto_avances   NUMBER;
    v_aporte_avances  NUMBER;
    v_nombre_avances  VARCHAR2(50);
    v_monto_savances  NUMBER;
    v_aporte_savances NUMBER;
    v_nombre_savances VARCHAR2(50);

BEGIN
    -- limpiar tablas
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_aporte_sbif';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_aporte_sbif';

    DBMS_OUTPUT.PUT_LINE('caso 2 - aporte SBIF año ' || v_año_actual);

    FOR reg_mes IN c_meses LOOP

        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- mes ' || SUBSTR(reg_mes.mes_anno,1,2) || '/' || SUBSTR(reg_mes.mes_anno,3) || ' ---');

        v_monto_avances := 0;   v_aporte_avances := 0;   v_nombre_avances := NULL;
        v_monto_savances := 0;  v_aporte_savances := 0;  v_nombre_savances := NULL;

        FOR reg IN c_transacciones(reg_mes.mes_anno) LOOP

            -- buscar el porcentaje que corresponde segun el tramo
            BEGIN
                SELECT porc_aporte_sbif INTO v_porc_aporte
                FROM tramo_aporte_sbif
                WHERE reg.monto_total_transaccion BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_porc_aporte := 0;
            END;

            -- calcular aporte
            v_aporte := ROUND(reg.monto_total_transaccion * v_porc_aporte / 100);

            INSERT INTO detalle_aporte_sbif
                (numrun, dvrun, nro_tarjeta, nro_transaccion, fecha_transaccion,
                 tipo_transaccion, monto_transaccion, aporte_sbif)
            VALUES
                (reg.numrun, reg.dvrun, reg.nro_tarjeta, reg.nro_transaccion,
                 reg.fecha_transaccion, reg.nombre_tptran_tarjeta,
                 reg.monto_total_transaccion, v_aporte);

            -- separar por tipo para el resumen
            IF reg.cod_tptran_tarjeta = 102 THEN
                v_monto_avances  := v_monto_avances + reg.monto_total_transaccion;
                v_aporte_avances := v_aporte_avances + v_aporte;
                v_nombre_avances := reg.nombre_tptran_tarjeta;
            ELSIF reg.cod_tptran_tarjeta = 103 THEN
                v_monto_savances  := v_monto_savances + reg.monto_total_transaccion;
                v_aporte_savances := v_aporte_savances + v_aporte;
                v_nombre_savances := reg.nombre_tptran_tarjeta;
            END IF;

            DBMS_OUTPUT.PUT_LINE('  ' || reg.numrun || '-' || reg.dvrun ||
                ' | ' || TO_CHAR(reg.fecha_transaccion,'DD/MM/YYYY') ||
                ' | monto: ' || reg.monto_total_transaccion ||
                ' | ' || v_porc_aporte || '% -> aporte: ' || v_aporte);

        END LOOP;

        -- insertar resumen, una fila por tipo si hay datos
        IF v_monto_avances > 0 THEN
            INSERT INTO resumen_aporte_sbif (mes_anno, tipo_transaccion, monto_total_transacciones, aporte_total_abif)
            VALUES (reg_mes.mes_anno, v_nombre_avances, v_monto_avances, v_aporte_avances);
            DBMS_OUTPUT.PUT_LINE('  avances: ' || v_monto_avances || ' -> aporte: ' || v_aporte_avances);
        END IF;

        IF v_monto_savances > 0 THEN
            INSERT INTO resumen_aporte_sbif (mes_anno, tipo_transaccion, monto_total_transacciones, aporte_total_abif)
            VALUES (reg_mes.mes_anno, v_nombre_savances, v_monto_savances, v_aporte_savances);
            DBMS_OUTPUT.PUT_LINE('  savances: ' || v_monto_savances || ' -> aporte: ' || v_aporte_savances);
        END IF;

    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'proceso terminado ok');
END;
/

EXIT;
