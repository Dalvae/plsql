-- caso 1 puntos circulo all the best
-- se procesan las transacciones del año anterior y se calculan los puntos
-- variable de cursor (sin param) y cursor explicito (con param)

SET SERVEROUTPUT ON SIZE UNLIMITED

-- variables bind para los tramos de puntos extras
VARIABLE tramo1_inf NUMBER
VARIABLE tramo1_sup NUMBER
VARIABLE tramo2_inf NUMBER
VARIABLE tramo2_sup NUMBER
VARIABLE tramo3_inf NUMBER

EXEC :tramo1_inf := 500000
EXEC :tramo1_sup := 700000
EXEC :tramo2_inf := 700001
EXEC :tramo2_sup := 900000
EXEC :tramo3_inf := 900001


DECLARE
    -- varray con los puntos normales y extras
    TYPE t_puntos IS VARRAY(4) OF NUMBER;
    v_puntos t_puntos := t_puntos(250, 300, 550, 700);

    -- registro para ir acumulando el resumen de cada mes
    TYPE t_resumen IS RECORD (
        monto_compras   NUMBER := 0,
        puntos_compras  NUMBER := 0,
        monto_avances   NUMBER := 0,
        puntos_avances  NUMBER := 0,
        monto_savances  NUMBER := 0,
        puntos_savances NUMBER := 0
    );
    v_resumen  t_resumen;

    -- cursor 1: variable de cursor sin parametro para los meses
    v_cursor_meses SYS_REFCURSOR;
    v_mes_anno     VARCHAR2(6);

    v_año_anterior NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;

    -- cursor 2: explicito con parametro, trae las transacciones del mes
    CURSOR c_transacciones(p_mes_anno VARCHAR2) IS
        SELECT c.numrun, c.dvrun, t.nro_tarjeta, tt.nro_transaccion,
               tt.fecha_transaccion, ttp.nombre_tptran_tarjeta,
               tt.monto_transaccion, tt.cod_tptran_tarjeta, c.cod_tipo_cliente
        FROM transaccion_tarjeta_cliente tt
        JOIN tarjeta_cliente t ON tt.nro_tarjeta = t.nro_tarjeta
        JOIN cliente c ON t.numrun = c.numrun
        JOIN tipo_transaccion_tarjeta ttp ON tt.cod_tptran_tarjeta = ttp.cod_tptran_tarjeta
        WHERE TO_CHAR(tt.fecha_transaccion, 'MMYYYY') = p_mes_anno
        ORDER BY tt.fecha_transaccion, c.numrun, tt.nro_transaccion;

    v_unidades      NUMBER;
    v_puntos_normal NUMBER;
    v_puntos_extra  NUMBER;
    v_puntos_total  NUMBER;


BEGIN
    -- truncar tablas antes de ejecutar
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_puntos_tarjeta_catb';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_puntos_tarjeta_catb';

    DBMS_OUTPUT.PUT_LINE('caso 1 - puntos CATB año ' || v_año_anterior);

    -- abrir la variable de cursor con los meses del año anterior
    OPEN v_cursor_meses FOR
        SELECT DISTINCT TO_CHAR(fecha_transaccion, 'MMYYYY') AS mes_anno
        FROM transaccion_tarjeta_cliente
        WHERE EXTRACT(YEAR FROM fecha_transaccion) = v_año_anterior
        ORDER BY mes_anno;

    LOOP
        FETCH v_cursor_meses INTO v_mes_anno;
        EXIT WHEN v_cursor_meses%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- mes ' || SUBSTR(v_mes_anno,1,2) || '/' || SUBSTR(v_mes_anno,3) || ' ---');

        -- resetear acumuladores
        v_resumen.monto_compras := 0;  v_resumen.puntos_compras := 0;
        v_resumen.monto_avances := 0;  v_resumen.puntos_avances := 0;
        v_resumen.monto_savances := 0;  v_resumen.puntos_savances := 0;

        -- recorrer transacciones del mes con el cursor con parametro
        FOR reg IN c_transacciones(v_mes_anno) LOOP

            -- calcular puntos normales (cada 100.000 = 250 pts)
            v_unidades := TRUNC(reg.monto_transaccion / 100000);
            v_puntos_normal := v_unidades * v_puntos(1);
            v_puntos_extra := 0;

            -- puntos extras solo para dueñas de casa (30) y pensionados/tercera edad (40)
            IF reg.cod_tipo_cliente IN (30, 40) THEN
                IF reg.monto_transaccion BETWEEN :tramo1_inf AND :tramo1_sup THEN
                    v_puntos_extra := v_unidades * v_puntos(2);
                ELSIF reg.monto_transaccion BETWEEN :tramo2_inf AND :tramo2_sup THEN
                    v_puntos_extra := v_unidades * v_puntos(3);
                ELSIF  reg.monto_transaccion >= :tramo3_inf THEN
                    v_puntos_extra := v_unidades * v_puntos(4);
                END IF;
            END IF;

            v_puntos_total := v_puntos_normal + v_puntos_extra;

            -- insertar en tabla detalle
            INSERT INTO detalle_puntos_tarjeta_catb
                (numrun, dvrun, nro_tarjeta, nro_transaccion, fecha_transaccion,
                 tipo_transaccion, monto_transaccion, puntos_allthebest)
            VALUES
                (reg.numrun, reg.dvrun, reg.nro_tarjeta, reg.nro_transaccion,
                 reg.fecha_transaccion, reg.nombre_tptran_tarjeta,
                 reg.monto_transaccion, v_puntos_total);

            -- acumular segun tipo de transaccion
            IF reg.cod_tptran_tarjeta = 101 THEN
                v_resumen.monto_compras  := v_resumen.monto_compras + reg.monto_transaccion;
                v_resumen.puntos_compras := v_resumen.puntos_compras + v_puntos_total;
            ELSIF reg.cod_tptran_tarjeta = 102 THEN
                v_resumen.monto_avances  := v_resumen.monto_avances + reg.monto_transaccion;
                v_resumen.puntos_avances := v_resumen.puntos_avances + v_puntos_total;
            ELSIF reg.cod_tptran_tarjeta = 103 THEN
                v_resumen.monto_savances  := v_resumen.monto_savances + reg.monto_transaccion;
                v_resumen.puntos_savances := v_resumen.puntos_savances + v_puntos_total;
            END IF;

            DBMS_OUTPUT.PUT_LINE('  run: ' || reg.numrun || '-' || reg.dvrun ||
                ' | ' || TO_CHAR(reg.fecha_transaccion,'DD/MM/YYYY') ||
                ' | monto: ' || reg.monto_transaccion ||
                ' | pts: ' || v_puntos_total);

        END LOOP;

        -- insertar resumen del mes
        INSERT INTO resumen_puntos_tarjeta_catb
            (mes_anno, monto_total_compras, total_puntos_compras,
             monto_total_avances, total_puntos_avances,
             monto_total_savances, total_puntos_savances)
        VALUES
            (v_mes_anno, v_resumen.monto_compras, v_resumen.puntos_compras,
             v_resumen.monto_avances, v_resumen.puntos_avances,
             v_resumen.monto_savances, v_resumen.puntos_savances);

        DBMS_OUTPUT.PUT_LINE('  resumen -> compras: ' || v_resumen.monto_compras ||
            ' | avances: ' || v_resumen.monto_avances ||
            ' | savances: ' || v_resumen.monto_savances);
    END LOOP;

    CLOSE v_cursor_meses;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'proceso terminado ok');
END;
/

EXIT;
